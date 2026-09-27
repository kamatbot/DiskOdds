import Foundation

nonisolated struct CleanupScanner: Sendable {
    let commands = CleanupCommands()

    func scan(context: CleanupContext) throws -> CleanupReport {
        var report = CleanupReport()
        if let fs = try? FileManager.default.attributesOfFileSystem(forPath: context.home.path) {
            report.capacity = (fs[.systemSize] as? NSNumber)?.int64Value ?? 0
            report.freeBytes = (fs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
        func add(_ url: URL, title: String, kind: CleanupKind, action: CleanupAction = .trash,
                 impact: String, recovery: String, project: String? = nil, simulator: String? = nil,
                 blocker: String? = nil) throws {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                if action != .guide { try CleanupFileSystem.validatePath(url) }
                let snapshot = try CleanupFileSystem.measure(url)
                guard snapshot.allocatedBytes > 0 || !snapshot.complete else { return }
                var reasons = ["Recognized \(kind.category.title.lowercased()) location.",
                               "Latest observed change: \(snapshot.newestModification.formatted(date: .abbreviated, time: .omitted)). This is not last-use telemetry."]
                if action == .trash { reasons.append("Rebuildable output or download cache; not your project root.") }
                if kind == .unavailableSimulator { reasons.append("simctl reports an unavailable device. Its app data may still be unique.") }
                if snapshot.hasSharedLinks { reasons.append("Multiply-linked file blocks are excluded from this estimate.") }
                if !snapshot.complete { reasons.append("Partial scan, mount boundary, protected content, or scan limit encountered. Cleanup blocked.") }
                report.items.append(CleanupItem(path: url.path, title: title, kind: kind, snapshot: snapshot,
                    action: action, odds: CleanupPolicy.confidence(kind: kind, snapshot: snapshot), reasons: reasons,
                    impact: impact, recovery: recovery,
                    blocker: blocker ?? (snapshot.complete ? nil : "Incomplete or protected contents; inspect manually."),
                    projectRoot: project, simulatorID: simulator))
            } catch is CancellationError { throw CancellationError() }
            catch { report.warnings.append("\(title): \(error.localizedDescription)") }
        }
        func children(_ url: URL) -> [URL] {
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            do { return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
            catch { report.warnings.append("Cannot list \(url.path): \(error.localizedDescription)"); return [] }
        }
        let derived = context.home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        for project in children(derived) {
            if CleanupPolicy.xcodeCaches.contains(project.lastPathComponent) {
                try add(project, title: project.lastPathComponent, kind: .xcodeCache,
                        impact: "Xcode will recreate its compiler caches. The next build may be slower.",
                        recovery: "Restore from Trash, or build your project again.")
            } else {
                for name in CleanupPolicy.derivedPaths {
                    try add(project.appendingPathComponent(name), title: "\(project.lastPathComponent) / \(name)", kind: .derivedBuild,
                            impact: "Removes generated build or index data, not SourcePackages or source code. The next build or indexing pass takes longer.",
                            recovery: "Restore from Trash, or reopen and rebuild the original project.")
                }
            }
        }
        for path in CleanupPolicy.cachePaths {
            try add(context.home.appendingPathComponent(path), title: URL(fileURLWithPath: path).lastPathComponent == "_cacache" ? "npm download cache" : URL(fileURLWithPath: path).lastPathComponent,
                    kind: .packageCache,
                    impact: "Packages may need downloading again. Offline builds can fail; custom changes inside a cache are not guaranteed recoverable.",
                    recovery: "Restore from Trash before emptying it, or let the package manager download again.")
        }
        // Project discovery is opt-in. Never traverse repository Git metadata.
        for root in context.projectRoots {
            var stack: [(URL, Int)] = [(root, 0)]
            var visited = 0
            while let (directory, depth) = stack.popLast() {
                try Task.checkCancellation()
                visited += 1
                if visited > 5_000 { report.warnings.append("Project discovery capped at 5,000 folders in \(root.path)."); break }
                let values = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("package.json").path) {
                    for suffix in CleanupPolicy.projectPaths {
                        let target = directory.appendingPathComponent(suffix)
                        guard FileManager.default.fileExists(atPath: target.path) else { continue }
                        var blocker: String?
                        do { try commands.verifyProjectCache(path: target.path, project: directory.path) }
                        catch { blocker = error.localizedDescription }
                        try add(target, title: "\(directory.lastPathComponent) / \(suffix)", kind: .projectCache,
                                impact: "Removes framework-generated cache only. The next dev server or build may start more slowly.",
                                recovery: "Restore from Trash or rerun your usual build command.", project: directory.path, blocker: blocker)
                    }
                }
                if depth < 4 {
                    for child in children(directory) where !child.lastPathComponent.hasPrefix(".")
                        && !["node_modules", "Library", "dist", "build", "target", "vendor", "Pods"].contains(child.lastPathComponent) {
                        stack.append((child, depth + 1))
                    }
                }
            }
        }
        do {
            let output = try commands.run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
            guard output.status == 0 else { throw CleanupFailure.rejected("simctl is unavailable. Install/select Xcode to inspect simulator devices.") }
            let inventory = try JSONDecoder().decode(SimulatorInventory.self, from: output.output)
            for device in inventory.devices.values.flatMap({ $0 }) {
                guard UUID(uuidString: device.udid) != nil else { continue }
                let unavailable = device.isAvailable == false
                let kind: CleanupKind = unavailable ? .unavailableSimulator : .availableSimulator
                let url = context.home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(device.udid)")
                try add(url, title: device.name + (unavailable ? " · unavailable" : " · \(device.state)"), kind: kind,
                        action: device.removable() ? .deleteSimulator : .guide,
                        impact: "Deleting a simulator permanently removes its installed apps, test databases, photos, and settings. It does not uninstall the shared runtime.",
                        recovery: "A new device can be created in Xcode, but its old app data is not recovered. Export anything important first.",
                        simulator: device.udid, blocker: device.state == "Booted" ? "Booted device. Not a cleanup target." : nil)
            }
            let runtimeOutput = try commands.run("/usr/bin/xcrun", ["simctl", "list", "runtimes", "--json"])
            if runtimeOutput.status == 0 {
                let runtimes = try JSONDecoder().decode(RuntimeInventory.self, from: runtimeOutput.output)
                for runtime in runtimes.runtimes {
                    guard let path = runtime.bundlePath, path.hasPrefix("/") else { continue }
                    try add(URL(fileURLWithPath: path), title: runtime.name + " runtime", kind: .runtime, action: .guide,
                            impact: "A runtime is shared by simulator devices and may be required by your projects. Mounted-runtime size is not guaranteed reclaimable storage.",
                            recovery: "Manage through Xcode Settings → Components (or Platforms). Download again when needed; requires network access.")
                }
            }
        } catch is CancellationError { throw CancellationError() }
        catch { report.warnings.append("Simulator inventory: \(error.localizedDescription)") }
        var stores: [(String, String)] = [
            (".ollama/models", "Ollama model store"), (".cache/huggingface/hub", "Hugging Face model store"),
            (".cache/huggingface/xet", "Hugging Face transfer cache"), (".lmstudio/models", "LM Studio models"),
            (".cache/lm-studio/models", "LM Studio legacy models")
        ]
        let env = ProcessInfo.processInfo.environment
        if let path = env["OLLAMA_MODELS"], path.hasPrefix("/") { stores.append((path, "Custom Ollama model store")) }
        if let path = env["HF_HUB_CACHE"], path.hasPrefix("/") { stores.append((path, "Custom Hugging Face model store")) }
        else if let path = env["HF_HOME"], path.hasPrefix("/") { stores.append((path + "/hub", "Custom Hugging Face model store")) }
        for (path, title) in stores {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : context.home.appendingPathComponent(path)
            try add(url, title: title, kind: .modelStore, action: .guide,
                    impact: "Models can be shared, private, fine-tuned, or needed offline. Their age does not establish that they are unused. Raw shared blobs are never bulk-deleted.",
                    recovery: "Use Ollama's model manager (ollama list / ollama rm <exact-model>), LM Studio's My Models, or the current hf cache tools. Confirm the original model is still downloadable first.")
        }
        report.items = CleanupPolicy.uniqueItems(report.items)
        report.scannedAt = .now
        return report
    }
}
