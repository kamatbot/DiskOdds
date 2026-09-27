import Foundation
import Testing
@testable import DiskOddsCore

private func projectItem(_ path: String, root: String) -> CleanupItem {
    CleanupItem(path: path, title: "Build", kind: .projectCache,
        snapshot: DiskSnapshot(identity: "test", signature: 0, allocatedBytes: 1024, logicalBytes: 1024,
                               entryCount: 1, newestModification: .distantPast, complete: true, hasSharedLinks: false),
        action: .trash, odds: 94, reasons: [], impact: "", recovery: "", blocker: nil, projectRoot: root)
}

@Test func projectBuildAllowlistRequiresSelectedRootAndProtectsCheckouts() {
    let home = URL(fileURLWithPath: "/Users/test")
    let root = "/Users/test/projects/App"
    let build = projectItem(root + "/.build/xcode-derived-data/Build", root: root)
    #expect(!CleanupPolicy.allowsTrash(build, context: CleanupContext(home: home)))
    let context = CleanupContext(home: home, projectRoots: [URL(fileURLWithPath: "/Users/test/projects")])
    #expect(CleanupPolicy.allowsTrash(build, context: context))
    let checkout = projectItem(root + "/.build/xcode-derived-data/SourcePackages", root: root)
    #expect(!CleanupPolicy.allowsTrash(checkout, context: context))
    let rootBuild = projectItem(root + "/.build", root: root)
    #expect(!CleanupPolicy.allowsTrash(rootBuild, context: context))
}

@Test func hardLinkedFilesAreNotPromisedAsReclaimable() throws {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = root.appendingPathComponent("file")
    try Data(repeating: 1, count: 8192).write(to: first)
    let single = try CleanupFileSystem.measure(root)
    try FileManager.default.linkItem(at: first, to: root.appendingPathComponent("alias"))
    let shared = try CleanupFileSystem.measure(root)
    #expect(shared.hasSharedLinks)
    #expect(shared.allocatedBytes < single.allocatedBytes)
}
