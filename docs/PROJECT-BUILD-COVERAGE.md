# Project-local build coverage

In addition to Xcode's default DerivedData location, opt-in project scanning recognizes these exact generated subdirectories:

```
.build/xcode-derived-data/Build
.build/xcode-derived-data/Index.noindex
.derivedData/Build
.derivedData/Index.noindex
DerivedData/Build
DerivedData/Index.noindex
.next/cache
.turbo
.parcel-cache
node_modules/.cache
```

The project must have `package.json`, `Package.swift`, an `.xcodeproj`, or an `.xcworkspace`. A proposed project-local target must be Git-ignored and contain no tracked files. This check repeats at cleanup time. Modified-in-the-last-seven-days targets have lower confidence. The entire `.build` folder, SourcePackages, checkouts, and arbitrary custom `-derivedDataPath` locations are not auto-targeted.

This extends the initial README's default-location coverage for common coding-agent build commands, including DiskOdds's own documented `.build/xcode-derived-data` build output. Open **Add folder…** and select a project or its parent projects directory to include these locations. Missing Git metadata blocks project-local cleanup rather than assuming the folder is disposable.
