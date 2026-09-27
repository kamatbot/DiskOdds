import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

nonisolated enum CleanupFileSystem {
    static func validatePath(_ url: URL) throws {
        let canonical = url.standardizedFileURL
        guard canonical.path == canonical.resolvingSymlinksInPath().path else {
            throw CleanupFailure.rejected("A symbolic link changes this path. It will not be cleaned.")
        }
        var current = URL(fileURLWithPath: "/")
        for component in canonical.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var st = stat()
            guard lstat(current.path, &st) == 0, st.st_mode & S_IFMT != S_IFLNK else {
                throw CleanupFailure.rejected("Path is missing, inaccessible, or contains a symbolic link.")
            }
        }
        var st = stat()
        guard lstat(canonical.path, &st) == 0, st.st_uid == geteuid() else {
            throw CleanupFailure.rejected("Cleanup is limited to files owned by your current account.")
        }
    }

    static func measure(_ url: URL, limit: Int = 300_000) throws -> DiskSnapshot {
        var root = stat()
        guard lstat(url.path, &root) == 0, root.st_mode & S_IFMT != S_IFLNK else {
            throw CleanupFailure.rejected("Cannot measure this location safely.")
        }
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var count = 0
        var newest = Date.distantPast
        var signature: UInt64 = 0
        var complete = true
        var shared = false
        var identities = Set<String>()
        func absorb(_ path: String, _ st: stat) {
            count += 1
            let identity = "\(st.st_dev):\(st.st_ino)"
            #if canImport(Darwin)
            let modified = st.st_mtimespec
            let changed = st.st_ctimespec
            #else
            let modified = st.st_mtim
            let changed = st.st_ctim
            #endif
            let date = Date(timeIntervalSince1970: Double(modified.tv_sec) + Double(modified.tv_nsec) / 1e9)
            newest = max(newest, date)
            let fingerprint = "\(path)|\(identity)|\(st.st_mode)|\(st.st_size)|\(modified.tv_sec):\(modified.tv_nsec)|\(changed.tv_sec):\(changed.tv_nsec)"
            var hash: UInt64 = 14695981039346656037
            for byte in fingerprint.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            signature ^= hash
            if identities.insert(identity).inserted {
                logical += max(0, Int64(st.st_size))
                if st.st_mode & S_IFMT == S_IFREG && st.st_nlink > 1 {
                    shared = true
                } else {
                    allocated += max(0, Int64(st.st_blocks)) * 512
                }
            }
        }
        absorb(url.path, root)
        if root.st_mode & S_IFMT == S_IFDIR {
            guard let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: nil, options: [],
                errorHandler: { _, _ in complete = false; return true }
            ) else { throw CleanupFailure.rejected("This directory cannot be read.") }
            while let child = enumerator.nextObject() as? URL {
                if count % 128 == 0 { try Task.checkCancellation() }
                guard count < limit else { complete = false; break }
                var st = stat()
                guard lstat(child.path, &st) == 0 else { complete = false; continue }
                if st.st_dev != root.st_dev { enumerator.skipDescendants(); complete = false; continue }
                if st.st_mode & S_IFMT == S_IFLNK { enumerator.skipDescendants() }
                let name = child.lastPathComponent.lowercased()
                if [".git", ".env", "credentials", "auth.json"].contains(name)
                    || name.hasSuffix(".xcarchive") || name.hasSuffix(".keychain-db") {
                    complete = false
                    enumerator.skipDescendants()
                }
                absorb(child.path, st)
            }
        }
        return DiskSnapshot(identity: "\(root.st_dev):\(root.st_ino)", signature: signature,
                            allocatedBytes: allocated, logicalBytes: logical, entryCount: count,
                            newestModification: newest, complete: complete, hasSharedLinks: shared)
    }
}
