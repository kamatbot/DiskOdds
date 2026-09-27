#!/usr/bin/env python3
"""Idempotent, pinned-upstream migration. Generated changes are committed, not required at app startup."""
from pathlib import Path
import json
import plistlib
import subprocess

root = Path(__file__).resolve().parents[1]

def update(relative, transform):
    path = root / relative
    before = path.read_text()
    after = transform(before)
    if before != after:
        path.write_text(after)
        print(relative)


def package(text):
    if 'name: "DiskOddsCore"' in text:
        return text
    anchor = '        .testTarget(\n            name: "RadixCoreTests",'
    assert text.count(anchor) == 1, "Unexpected upstream Package.swift"
    text = text.replace('                "App",', '                "App",\n                "DeveloperCleanup",', 1)
    return text.replace(anchor, '''        .target(
            name: "DiskOddsCore",
            path: "Radix/DeveloperCleanup/Core"
        ),
        .testTarget(
            name: "DiskOddsCoreTests",
            dependencies: ["DiskOddsCore"],
            path: "DiskOddsCoreTests"
        ),
''' + anchor, 1)


def project(text):
    if 'PRODUCT_BUNDLE_IDENTIFIER = com.kamatbot.DiskOdds;' in text:
        return text
    old = 'PRODUCT_BUNDLE_IDENTIFIER = com.colinkim.Radix;\n\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";'
    assert text.count(old) == 2, "Unexpected upstream app build settings"
    text = text.replace(old, 'PRODUCT_BUNDLE_IDENTIFIER = com.kamatbot.DiskOdds;\n\t\t\t\tPRODUCT_NAME = DiskOdds;')
    text = text.replace('com.colinkim.RadixCoreTests', 'com.kamatbot.DiskOddsExplorerTests')
    text = text.replace('INFOPLIST_KEY_CFBundleDisplayName = Radix;', 'INFOPLIST_KEY_CFBundleDisplayName = DiskOdds;')
    text = text.replace('MARKETING_VERSION = 1.8.0;', 'MARKETING_VERSION = 0.1.0;')
    text = text.replace('Radix.app', 'DiskOdds.app')
    text = text.replace('42MBX5D86L', '""').replace('"Developer ID Application"', '"-"')
    return text

update('Package.swift', package)
update('Radix.xcodeproj/project.pbxproj', project)
for path in (root / 'Radix.xcodeproj/xcshareddata/xcschemes').glob('*.xcscheme'):
    update(str(path.relative_to(root)), lambda text: text.replace('Radix.app', 'DiskOdds.app'))
info_path = root / 'Radix/Info.plist'
info = plistlib.loads(info_path.read_bytes())
for key in ['SUFeedURL', 'SUPublicEDKey', 'SUEnableAutomaticChecks', 'SUScheduledCheckInterval']:
    info.pop(key, None)
for document in info.get('CFBundleDocumentTypes', []):
    document['LSHandlerRank'] = 'Alternate'
info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
strings_path = root / 'Radix/InfoPlist.xcstrings'
strings = json.loads(strings_path.read_text())
for key in ['CFBundleDisplayName', 'CFBundleName']:
    for localization in strings['strings'][key]['localizations'].values():
        localization['stringUnit']['value'] = 'DiskOdds'
strings_path.write_text(json.dumps(strings, ensure_ascii=False, indent=2) + '\n')
original_readme = root / 'docs/RADIX-UPSTREAM.md'
if not original_readme.exists():
    original_readme.parent.mkdir(exist_ok=True)
    result = subprocess.run(['git', 'show', '14a76df4fe626dcdefc4f2abbc868dff4bbbd6e4:README.md'], cwd=root,
                            capture_output=True, check=True)
    original_readme.write_bytes(result.stdout)
assert 'SUFeedURL' not in plistlib.loads(info_path.read_bytes())
assert 'startingUpdater: true' not in (root / 'Radix/RadixApp.swift').read_text()
print('DiskOdds identity, independent test target, and update-channel isolation configured.')
