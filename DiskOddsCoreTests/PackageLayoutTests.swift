import Foundation
import Testing
@testable import DiskOddsCore

@Test func cleanupCoreHasIndependentAutomaticallyDiscoveredTarget() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
    #expect(package.contains("name: \"DiskOddsCore\""))
    #expect(package.contains("path: \"Radix/DeveloperCleanup/Core\""))
    let core = root.appendingPathComponent("Radix/DeveloperCleanup/Core")
    let files = try FileManager.default.contentsOfDirectory(at: core, includingPropertiesForKeys: nil)
    #expect(files.filter { $0.pathExtension == "swift" }.count >= 5)
    #expect(!files.contains { $0.lastPathComponent == "Package.swift" })
}

@Test func environmentFilesDisableCleanupOfOtherwiseRecognizedOutput() throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("fixture-only".utf8).write(to: root.appendingPathComponent(".env.local"))
    #expect(!(try CleanupFileSystem.measure(root)).complete)
}
