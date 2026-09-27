# Cleanup safety design

## Trust contract

DiskOdds estimates whether a recognized item is a plausible cleanup candidate. It cannot know the user's future needs, guarantee redownload availability, or prove a cache contains no manually saved data. Percentages are versioned rule outputs, not learned empirical probabilities. No score alone authorizes deletion.

The cleanup workspace has two executable actions: macOS Trash for narrowly allowlisted generated/cache locations, and `xcrun simctl delete <exact UUID>` for a selected unavailable, shut-down simulator. Runtimes and shared model stores are inventory/guidance only. The original Radix explorer is a separate manual file-management interface; cleanup confidence rules are not a claim that arbitrary explorer deletions are safe.

## Boundaries

The default DerivedData parent, project roots, source package checkouts, archives, credentials, agent sessions, Git metadata, and shared model blobs are never broad cleanup targets. Project scans require the user's selected root and check known framework cache paths against Git's ignored/tracked state. A path prefix is compared as components, not as a string prefix. A selection cannot include overlapping ancestors/descendants.

Executable targets must resolve without symlink ancestors and be owned by the current account. Enumeration does not follow symlink entries or cross device boundaries. Protected-content markers and unreadable or capped traversals disable cleanup rather than silently authorizing a partial result. Limits are 300,000 entries per measured candidate and 5,000 directories / four levels for each opted-in project-discovery root. There is no administrator helper, shell command interpolation, sudo, or recursive force-delete.

## Revalidation and residual races

The snapshot hashes path, file identity, mode, size, mtime and ctime including nanoseconds. Full-plan preflight happens before the first write, then each item is checked again just before its action. Simulator inventory and project Git eligibility are refreshed. A failed command, changed snapshot, keep rule, or recognized live developer process stops the operation. Commands are passed as executable plus argument arrays, bounded by a timeout and captured without pipe deadlocks.

These checks reduce stale-plan and accidental-target risks; they do not lock every writer or eliminate all time-of-check/time-of-use races. Process-name checks are intentionally conservative but cannot detect every application or open descriptor. Close development tasks and retain backups. Managed model/reference graphs need their owning tool's removal APIs, not raw blob deletion.

## Recovery and accounting

A Trash receipt records original and resulting paths and estimated staged bytes. Only Finder emptying frees that space, and only the filesystem can report actual availability. Simulator receipts never pretend permanent deletion is recoverable. A fresh scan updates volume metrics. Parent/child candidate overlap is removed; repeated inodes are counted once within a candidate and multiply-linked regular file blocks are excluded from estimates. APFS-clone and snapshot references are not fully measurable here. Mounted runtime footprints must not be added to a promised reclaim total.

## macOS release validation checklist

Run all core tests and build the complete app. Manually check scan/cancel, filter/sort, selecting no candidates by default, map-to-inspector selection, keep rules, folder scope, missing Xcode and permission warnings. In a disposable local test directory, verify Trash receipts and restoration. With a disposable unavailable simulator only, verify exact UUID confirmation, permanent-data warning, changed/booted state rejection and a post-action rescan. Exercise plan-change and tool-start races. Never run destructive validation against personal simulator data. A screenshot/demo is not destructive-path validation.

## Primary documentation

- Apple Xcode component management: https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components
- Local Xcode CLI contract: `xcrun simctl help list` and `xcrun simctl help delete` on the user's selected Xcode version.
- Hugging Face cache structure and shared references: https://huggingface.co/docs/huggingface_hub/guides/manage-cache
- Ollama model storage and environment configuration: https://docs.ollama.com/faq

The application does not load these pages or send file lists off the device.
