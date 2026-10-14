import Foundation
import Testing
@testable import DiskOddsCore

private func traversalFixture() throws -> URL {
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func wideCleanupTreeDoesNotHoldEverySiblingOpen() throws {
    let root = try traversalFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    for index in 0..<512 {
        let child = root.appendingPathComponent("cache-\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: child.appendingPathComponent("entry"))
    }
    let result = try CleanupFileSystem.measure(root)
    #expect(result.complete)
    #expect(result.entryCount == 1025)
    #expect(result == (try CleanupFileSystem.measure(root)))
}

@Test func veryDeepCleanupTreeFailsClosed() throws {
    let root = try traversalFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    var child = root
    for _ in 0..<140 {
        child.appendPathComponent("d", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
    }
    let result = try CleanupFileSystem.measure(root)
    #expect(!result.complete)
    #expect(result.entryCount <= 129)
}

@Test func cleanupMeasurementRejectsASymlinkRoot() throws {
    let root = try traversalFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target", isDirectory: true)
    let link = root.appendingPathComponent("link")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(throws: CleanupFailure.self) { try CleanupFileSystem.measure(link) }
}

@Test func cleanupMeasurementStillSupportsARegularFile() throws {
    let root = try traversalFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file")
    try Data("content".utf8).write(to: file)
    let result = try CleanupFileSystem.measure(file)
    #expect(result.complete)
    #expect(result.entryCount == 1)
    #expect(result.logicalBytes == 7)
}

@Test func protectedDirectoryNamesAreCaseInsensitiveAndNotDescended() throws {
    let root = try traversalFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let protected = root.appendingPathComponent("backup.XCARCHIVE", isDirectory: true)
    try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: protected.appendingPathComponent("archive"))
    let result = try CleanupFileSystem.measure(root)
    #expect(!result.complete)
    #expect(result.entryCount == 2)
}

@Test func hardLinkedFilesAreNotCountedAsReclaimableBlocks() throws {
    let root = try traversalFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("original")
    try Data(repeating: 3, count: 1_048_576).write(to: file)
    try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("alias"))
    let result = try CleanupFileSystem.measure(root)
    #expect(result.complete)
    #expect(result.hasSharedLinks)
    #expect(result.entryCount == 3)
    #expect(result.allocatedBytes < 1_048_576)
}
