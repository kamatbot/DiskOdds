import Foundation

actor CleanupExecutor {
    private let commands = CleanupCommands()

    func execute(items: [CleanupItem], context: CleanupContext, keptPaths: Set<String>,
                 acknowledged: Bool, simulatorConfirmation: String) throws -> [CleanupReceipt] {
        guard acknowledged, !items.isEmpty, !CleanupPolicy.overlaps(items.map(\.path)) else {
            throw CleanupFailure.rejected("Confirm a non-overlapping selection before cleaning.")
        }
        if items.contains(where: { $0.action == .deleteSimulator }) && simulatorConfirmation != "DELETE" {
            throw CleanupFailure.rejected("Type DELETE to confirm permanent simulator data removal.")
        }
        let busy = try commands.busyTools()
        guard busy.isEmpty else { throw CleanupFailure.rejected("Close these tools and stop their tasks first: " + busy.joined(separator: ", ")) }
        // Validate the entire plan before its first write, then each target again before use.
        for item in items { try validate(item, context: context, keptPaths: keptPaths) }
        var receipts: [CleanupReceipt] = []
        for item in items {
            try Task.checkCancellation()
            do {
                let nowBusy = try commands.busyTools()
                guard nowBusy.isEmpty else { throw CleanupFailure.rejected("A development process started. Remaining cleanup was stopped.") }
                try validate(item, context: context, keptPaths: keptPaths)
                var trashPath: String?
                switch item.action {
                case .trash:
                    #if os(macOS)
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resultingURL)
                    trashPath = resultingURL?.path
                    #else
                    throw CleanupFailure.rejected("Moving to Trash is supported only on macOS.")
                    #endif
                case .deleteSimulator:
                    guard let id = item.simulatorID, UUID(uuidString: id) != nil else {
                        throw CleanupFailure.rejected("Invalid simulator identifier.")
                    }
                    let result = try commands.run("/usr/bin/xcrun", ["simctl", "delete", id], timeout: 60)
                    guard result.status == 0 else { throw CleanupFailure.rejected("simctl did not confirm deletion. Rescan to inspect current device state.") }
                case .guide:
                    throw CleanupFailure.rejected("Managed stores and runtimes cannot be deleted here.")
                }
                receipts.append(CleanupReceipt(id: UUID(), date: .now, originalPath: item.path, trashPath: trashPath,
                    stagedBytes: item.action == .trash ? item.snapshot.allocatedBytes : 0,
                    message: item.action == .trash ? "Moved to Trash. Space is not reclaimed until you empty Trash in Finder." : "Simulator deleted permanently. Rescan for actual volume availability.", succeeded: true))
            } catch {
                receipts.append(CleanupReceipt(id: UUID(), date: .now, originalPath: item.path, trashPath: nil,
                    stagedBytes: 0, message: error.localizedDescription, succeeded: false))
                break
            }
        }
        return receipts
    }

    private func validate(_ item: CleanupItem, context: CleanupContext, keptPaths: Set<String>) throws {
        guard item.actionable, !keptPaths.contains(where: { $0 == item.path || CleanupPolicy.contains($0, item.path) }) else {
            throw CleanupFailure.rejected("This item is protected or not actionable.")
        }
        let url = URL(fileURLWithPath: item.path)
        try CleanupFileSystem.validatePath(url)
        guard try CleanupFileSystem.measure(url) == item.snapshot else {
            throw CleanupFailure.rejected("Files changed since the scan. Rescan and review the new plan.")
        }
        switch item.action {
        case .trash:
            guard CleanupPolicy.allowsTrash(item, context: context) else {
                throw CleanupFailure.rejected("Path does not match a supported cleanup rule.")
            }
            if let project = item.projectRoot { try commands.verifyProjectCache(path: item.path, project: project) }
        case .deleteSimulator:
            guard let id = item.simulatorID, UUID(uuidString: id) != nil,
                  item.kind == .unavailableSimulator,
                  item.path == context.home.appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(id)").path else {
                throw CleanupFailure.rejected("Simulator target is outside the default device set.")
            }
            let output = try commands.run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
            guard output.status == 0 else { throw CleanupFailure.rejected("Cannot revalidate simulator state.") }
            let inventory = try JSONDecoder().decode(SimulatorInventory.self, from: output.output)
            guard inventory.devices.values.flatMap({ $0 }).contains(where: { $0.udid == id && $0.removable() }) else {
                throw CleanupFailure.rejected("The simulator is no longer unavailable and shut down.")
            }
        case .guide:
            throw CleanupFailure.rejected("Use the owning application for this item.")
        }
    }
}
