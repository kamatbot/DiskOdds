# DiskOdds

**Make room to build.** Native macOS storage analysis for developers working with coding agents, Xcode, simulators, web frameworks, and local AI models.

DiskOdds extends [Radix by Colin Kim](https://github.com/colinvkim/Radix). The complete upstream source, tests, assets, and history are retained, along with its [MIT license](LICENSE). The original disk explorer remains available beside the new developer-cleanup workspace. The upstream auto-update feed is disabled and DiskOdds uses its own bundle identity.

## Developer cleanup

The new home screen combines actual home-volume free space, a developer-footprint treemap, sortable/filterable candidates, and an evidence inspector. Tile area represents observed disk footprint; color and a percentage represent rule-based cleanup confidence. Nothing is selected by default.

| Category | Detection and action |
|---|---|
| Xcode leftovers | Per-project `Build` and `Index.noindex` directories under default DerivedData, plus known compiler caches. Review and move to Trash. SourcePackages and archives are excluded. |
| Package caches | Homebrew, CocoaPods, pip, uv, SwiftPM download caches, and npm `_cacache`. Review redownload/offline trade-offs, then move to Trash. |
| Project caches | Opt-in project folders; known Next.js, Turborepo, Parcel, and dependency-tool caches. Require both Git-ignored paths and no tracked files. Never remove entire repositories or node_modules. |
| Simulator devices | Live `simctl` inventory. Only unavailable, shut-down devices are executable candidates. Exact UUID deletion requires a separate `DELETE` confirmation because simulator app data is permanent. |
| Simulator runtimes | Inventory with guidance to use Xcode's component manager. No raw deletion of shared or mounted runtime bundles. |
| Local models | Footprint and guidance for Ollama, Hugging Face hub/Xet, and LM Studio model stores. These are managed-only items in this release, not automatically deleted or claimed to be unused. |

This catches common outputs created during Codex/Claude development without deleting agent conversations, credentials, or working trees. It does not infer which agent created a file from its name.

### What the odds mean

**Percentages are transparent heuristic scores, not statistically calibrated probabilities or guarantees.** An unchanged recognized Xcode cache/build directory can score 98%; a package cache 96%; an ignored project cache 94%. Recent changes reduce these scores to 65%. The seven-day threshold uses the newest observed modification in the candidate tree, not just its parent directory. Modification time is not proof of last use.

Unavailable simulators remain at 80% because their app data can be unique. Model stores stay at 40%, available devices at 45%, and runtimes at 50%; these scores do not establish that a model/runtime is unused. Incomplete scans score 0% and cannot be cleaned. The `95%+` button selects eligible candidates only after an explicit click and still requires review.

### Safety and space accounting

Scans are read-only, cancellable, bounded, and local. Before cleanup, the entire plan and then each target are revalidated: known path, ownership, symlink ancestry, metadata fingerprint, keep rules, Git tracking, and simulator state where applicable. Recognized running development tools block cleanup; there is no force override. Errors stop the remaining plan.

Builds and caches go to macOS Trash, with receipts and Finder links. **Moving files to Trash does not reclaim space until you empty it yourself.** Test your projects first. DiskOdds never automatically empties Trash. Simulator deletion is permanent and is clearly separated from recoverable cleanup.

Footprint estimates use allocated blocks and exclude multiply-linked regular-file blocks. Parent/child candidates are de-duplicated. APFS clones, snapshots, shared files, permissions, and mounted runtimes mean estimated footprint is not a promise of free space. Actual volume availability is refreshed by a rescan.

## Build and test

Requires macOS 14 or later and Xcode 26.6 / Swift 6.2 or later. The project and scheme retain the upstream name to simplify maintenance; the resulting app is **DiskOdds.app**.

```bash
swift test
xcodebuild -project Radix.xcodeproj -scheme Radix \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-derived-data CODE_SIGNING_ALLOWED=NO build
open -n .build/xcode-derived-data/Build/Products/Debug/DiskOdds.app
```

For a clearly labeled, non-destructive design preview:

```bash
open -n .build/xcode-derived-data/Build/Products/Debug/DiskOdds.app --args --diskodds-demo
```

`DiskOddsCoreTests` covers confidence rules, path boundaries, overlapping selections, changed metadata, symlink rejection, protected contents, and simulator eligibility. The original `RadixCoreTests` suite is retained. The new core is also portable enough to test on Linux, but the app and Trash integration require macOS. This repository is a source/developer build, not a signed or notarized distribution.

## Scope and limitations

The first cleanup UI is in English; the inherited explorer retains its existing locales. Default Xcode locations and common model directories are supported. Custom DerivedData directories, arbitrary temporary folders, `.build`, general `build`/`dist` folders, Docker volumes, agent worktree pruning, and model-level deletion are deliberately not inferred as disposable. Add explicit, tested adapters rather than broad filename rules. GUI apps may not inherit shell environment variables for custom model stores.

Read [the safety design and validation checklist](docs/CLEANUP-SAFETY.md), [upstream provenance](DISKODDS-UPSTREAM.md), and [the preserved upstream README](docs/RADIX-UPSTREAM.md).
