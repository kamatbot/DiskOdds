import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

nonisolated struct CleanupCommandResult: Sendable {
    let status: Int32
    let output: Data
}

nonisolated struct CleanupCommands: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> CleanupCommandResult {
        guard ["/usr/bin/xcrun", "/usr/bin/git", "/bin/ps"].contains(executable) else {
            throw CleanupFailure.rejected("Command is not allowlisted.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                               "LANG": "en_US.UTF-8", "GIT_CONFIG_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0"]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: output.path, contents: nil,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw CleanupFailure.rejected("Cannot create private command output.")
        }
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled || Date() >= deadline {
                process.terminate()
                let grace = Date().addingTimeInterval(1)
                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.025) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw CleanupFailure.rejected("Command timed out or was cancelled. Nothing else was removed.")
            }
            Thread.sleep(forTimeInterval: 0.025)
        }
        process.waitUntilExit()
        let size = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 16 * 1024 * 1024 else { throw CleanupFailure.rejected("Command output exceeded the safety limit.") }
        return CleanupCommandResult(status: process.terminationStatus, output: try Data(contentsOf: output))
    }

    func busyTools() throws -> [String] {
        let result = try run("/bin/ps", ["-axo", "comm="])
        guard result.status == 0, let text = String(data: result.output, encoding: .utf8), !text.isEmpty else {
            throw CleanupFailure.rejected("Could not check running tools. Cleanup is disabled until this check succeeds.")
        }
        let names: Set<String> = ["xcode", "xcodebuild", "simulator", "swift", "swift-frontend", "swift-build",
                                  "clang", "clang++", "node", "npm", "pnpm", "yarn", "bun", "uv", "pip", "pip3",
                                  "python", "python3", "brew", "pod", "codex", "claude"]
        return Array(Set(text.split(separator: "\n").compactMap {
            let name = URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).lastPathComponent
            return names.contains(name.lowercased()) ? name : nil
        })).sorted()
    }

    func verifyProjectCache(path: String, project: String) throws {
        guard CleanupPolicy.contains(project, path) else { throw CleanupFailure.rejected("Outside project boundary.") }
        let relative = String(path.dropFirst(project.count + 1))
        let prefix = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", project]
        let ignored = try run("/usr/bin/git", prefix + ["check-ignore", "-q", "--", relative])
        let tracked = try run("/usr/bin/git", prefix + ["ls-files", "-z", "--", relative])
        guard ignored.status == 0, tracked.status == 0, tracked.output.isEmpty else {
            throw CleanupFailure.rejected("Project cache is not both Git-ignored and free of tracked files.")
        }
    }
}

nonisolated struct SimulatorInventory: Decodable, Sendable {
    let devices: [String: [SimulatorDevice]]
}
nonisolated struct SimulatorDevice: Decodable, Sendable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    func removable() -> Bool { UUID(uuidString: udid) != nil && state == "Shutdown" && isAvailable == false }
}
nonisolated struct RuntimeInventory: Decodable, Sendable {
    let runtimes: [SimulatorRuntime]
}
nonisolated struct SimulatorRuntime: Decodable, Sendable {
    let name: String
    let identifier: String
    let bundlePath: String?
}
