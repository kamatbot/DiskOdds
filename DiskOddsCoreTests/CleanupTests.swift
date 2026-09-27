import Foundation
import Testing
@testable import DiskOddsCore

private func snapshot(days: Double = 30, complete: Bool = true) -> DiskSnapshot {
    DiskSnapshot(identity: "1:1", signature: 0, allocatedBytes: 1024, logicalBytes: 1024,
                 entryCount: 1, newestModification: .now.addingTimeInterval(-days * 86400),
                 complete: complete, hasSharedLinks: false)
}
private func item(_ path: String, kind: CleanupKind = .derivedBuild, action: CleanupAction = .trash) -> CleanupItem {
    CleanupItem(path: path, title: "Test", kind: kind, snapshot: snapshot(), action: action,
                odds: 98, reasons: [], impact: "", recovery: "", blocker: nil)
}

@Test func oldBuildHasHighButNotCertainConfidence() {
    #expect(CleanupPolicy.confidence(kind: .derivedBuild, snapshot: snapshot()) == 98)
}
@Test func recentlyModifiedBuildIsNotAQuickWin() {
    #expect(CleanupPolicy.confidence(kind: .derivedBuild, snapshot: snapshot(days: 0.1)) < 95)
}
@Test func incompleteScanNeverGetsPositiveConfidence() {
    for kind in [CleanupKind.derivedBuild, .packageCache, .modelStore, .unavailableSimulator] {
        #expect(CleanupPolicy.confidence(kind: kind, snapshot: snapshot(complete: false)) == 0)
    }
}
@Test func modelsAndSimulatorDataAreNeverHighConfidence() {
    #expect(CleanupPolicy.confidence(kind: .modelStore, snapshot: snapshot(days: 900)) == 40)
    #expect(CleanupPolicy.confidence(kind: .unavailableSimulator, snapshot: snapshot(days: 900)) == 80)
}
@Test func pathBoundariesAreComponentAware() {
    #expect(CleanupPolicy.contains("/Users/a/Cache", "/Users/a/Cache/file"))
    #expect(!CleanupPolicy.contains("/Users/a/Cache", "/Users/a/Cache-keep/file"))
    #expect(!CleanupPolicy.contains("/Users/a/Cache", "/Users/a/Cache/../Sources"))
}
@Test func duplicateAndNestedPlansAreRejected() {
    #expect(CleanupPolicy.overlaps(["/a/cache", "/a/cache"]))
    #expect(CleanupPolicy.overlaps(["/a/cache", "/a/cache/child"]))
    #expect(!CleanupPolicy.overlaps(["/a/cache", "/a/cache2"]))
}
@Test func dedupDoesNotCountNestedModelStoresTwice() {
    #expect(CleanupPolicy.uniqueItems([item("/a"), item("/a/b"), item("/a")]).count == 1)
}
@Test func allowlistNeverAllowsProjectOrDerivedDataRoots() {
    let context = CleanupContext(home: URL(fileURLWithPath: "/Users/test"))
    #expect(!CleanupPolicy.allowsTrash(item("/Users/test"), context: context))
    #expect(!CleanupPolicy.allowsTrash(item("/Users/test/Library/Developer/Xcode/DerivedData"), context: context))
    #expect(CleanupPolicy.allowsTrash(item("/Users/test/Library/Developer/Xcode/DerivedData/App-abc/Build"), context: context))
    #expect(!CleanupPolicy.allowsTrash(item("/Users/test/Library/Developer/Xcode/DerivedData/App-abc/SourcePackages"), context: context))
}
@Test func managedStoreCannotBeForgedIntoTrashAction() {
    let context = CleanupContext(home: URL(fileURLWithPath: "/Users/test"))
    #expect(!CleanupPolicy.allowsTrash(item("/Users/test/.ollama/models", kind: .modelStore), context: context))
}
@Test func simulatorMustBeValidUnavailableAndShutdown() throws {
    let json = #"{"devices":{"runtime":[{"udid":"8E5A6899-3005-4717-991F-A4D20B30D548","name":"iPhone","state":"Shutdown","isAvailable":false}]}}"#
    let inventory = try JSONDecoder().decode(SimulatorInventory.self, from: Data(json.utf8))
    #expect(inventory.devices["runtime"]?.first?.removable() == true)
    #expect(!SimulatorDevice(udid: "../../home", name: "x", state: "Shutdown", isAvailable: false).removable())
    #expect(!SimulatorDevice(udid: UUID().uuidString, name: "x", state: "Booted", isAvailable: false).removable())
    #expect(!SimulatorDevice(udid: UUID().uuidString, name: "x", state: "Shutdown", isAvailable: nil).removable())
}
@Test func filesystemDetectsChangedDescendantsAndLimits() throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file")
    try Data("first".utf8).write(to: file)
    let first = try CleanupFileSystem.measure(root)
    #expect(first.complete)
    #expect(first == (try CleanupFileSystem.measure(root)))
    try Data("changed and longer".utf8).write(to: file)
    #expect(first != (try CleanupFileSystem.measure(root)))
    #expect(!(try CleanupFileSystem.measure(root, limit: 1)).complete)
}
@Test func symlinkAncestorsAreRejectedWithoutFollowingThem() throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let real = root.appendingPathComponent("real")
    try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
    let link = root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    #expect(throws: (any Error).self) { try CleanupFileSystem.validatePath(link) }
}
@Test func protectedContentsMakePlanIncomplete() throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(!(try CleanupFileSystem.measure(root)).complete)
}
@Test func commandsRejectUnknownExecutablesBeforeRunning() {
    #expect(throws: (any Error).self) { try CleanupCommands().run("/bin/sh", ["-c", "echo unsafe"]) }
}
