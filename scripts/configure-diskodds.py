#!/usr/bin/env python3
"""Idempotently finish fork integration; all generated changes are committed before validation."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
assert 'com.kamatbot.DiskOdds;' in (root / 'Radix.xcodeproj/project.pbxproj').read_text()
assert 'name: "DiskOddsCore"' in (root / 'Package.swift').read_text()

def update(relative, old, new):
    path = root / relative
    text = path.read_text()
    if new in text:
        return
    assert text.count(old) == 1, f'Unexpected migration input: {relative}'
    path.write_text(text.replace(old, new, 1))
    print(relative)

# The upstream audit enumerated every non-UI file into a single package target.
# DiskOddsCore is a separately compiled, automatically discovered target with its own audit.
update('RadixCoreTests/LocalizationCatalogTests.swift',
       '["App", "Features", "Shared"].contains(firstComponent)',
       '["App", "Features", "Shared", "DeveloperCleanup"].contains(firstComponent)')
# Swift's catalog format escapes literal percentages. Normalize them when comparing
# a source interpolation template with its real compiled localization key.
update('RadixCoreTests/LocalizationCatalogTests.swift',
       'options: .regularExpression\n        )\n    }\n\n    private func replacingSwiftInterpolations',
       'options: .regularExpression\n        ).replacingOccurrences(of: "%%", with: "%")\n    }\n\n    private func replacingSwiftInterpolations')

translations = json.loads((root / 'scripts/diskodds-ui-translations.json').read_text())
locales = ['de', 'es', 'fr', 'it', 'ru', 'zh-Hans']
# A brand name is invariant in every locale.
translations['DiskOdds'] = ['DiskOdds'] * len(locales)
catalog_path = root / 'Radix/Localizable.xcstrings'
catalog = json.loads(catalog_path.read_text())
for key, values in translations.items():
    assert len(values) == len(locales), f'Incomplete translations: {key}'
    specifiers = lambda value: sorted(re.findall(r'%(?:[0-9]+\$)?(?:lld|ld|llu|lu|d|u|f|@)', value))
    assert all(specifiers(key) == specifiers(value) for value in values), f'Changed placeholders: {key}'
    catalog['strings'][key] = {
        'comment': 'DiskOdds developer-cleanup interface. Confidence is heuristic, not a probability guarantee.',
        'extractionState': 'manual',
        'localizations': {locale: {'stringUnit': {'state': 'translated', 'value': value}}
                          for locale, value in [('en', key), *zip(locales, values)]}
    }
catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')

update('Radix/DeveloperCleanup/Core/CleanupExecutor.swift',
       '        let url = URL(fileURLWithPath: item.path)\n        try CleanupFileSystem.validatePath(url)',
       '''        #if os(macOS)
        let runningApp = Bundle.main.bundleURL.path
        guard item.path != runningApp, !CleanupPolicy.contains(item.path, runningApp) else {
            throw CleanupFailure.rejected("The selected folder contains the running DiskOdds app. Keep it and clean other builds.")
        }
        #endif
        let url = URL(fileURLWithPath: item.path)
        try CleanupFileSystem.validatePath(url)''')
update('Radix/DeveloperCleanup/Core/CleanupFileSystem.swift',
       '                    || name.hasSuffix(".xcarchive") || name.hasSuffix(".keychain-db") {',
       '''                    || name.hasPrefix(".env.") || name.hasSuffix(".p12") || name.hasSuffix(".mobileprovision")
                    || name.hasSuffix(".xcarchive") || name.hasSuffix(".keychain-db") {''')

update('README.md',
       'Custom DerivedData directories, arbitrary temporary folders, `.build`, general `build`/`dist` folders, Docker volumes, agent worktree pruning, and model-level deletion are deliberately not inferred as disposable.',
       'Known project-local DerivedData subdirectories are supported through opt-in folders; see [project build coverage](docs/PROJECT-BUILD-COVERAGE.md). Arbitrary custom DerivedData paths, temporary folders, the whole `.build` directory, general `build`/`dist` folders, Docker volumes, agent worktree pruning, and model-level deletion are deliberately not inferred as disposable.')
update('README.md',
       'The first cleanup UI is in English; the inherited explorer retains its existing locales.',
       'The cleanup interface includes catalog entries for the inherited locales; detailed rule explanations and some dynamic tool text remain English in this first release. The inherited explorer retains its existing locales.')
print(f'Integrated {len(translations)} localized UI keys and independent-core source coverage without disabling the audits.')
