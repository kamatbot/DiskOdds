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

    /// Measures allocated size without following symlinks or materializing a URL per entry.
    /// Foundation's directory enumerator spends most of its time on those URL objects, which
    /// dominates cleanup scans of DerivedData, package caches, and model stores.
    static func measure(_ url: URL, limit: Int = 300_000) throws -> DiskSnapshot {
        try Task.checkCancellation()
        let rootPath = fileSystemBytes(url)
        var root = stat()
        let opened = openForMeasure(rootPath, metadata: &root)
        var allocated: Int64 = 0
        var logical: Int64 = 0
        var count = 0
        var newest = Date.distantPast
        var signature: UInt64 = 0
        var complete = true
        var shared = false
        var identities = Set<Identity>()
        var stack: [DirectoryFrame] = []
        defer {
            for frame in stack { closedir(frame.stream) }
        }
        switch opened {
        case .unsafe:
            throw CleanupFailure.rejected("Cannot measure this location safely.")
        case .unreadable:
            throw CleanupFailure.rejected("This directory cannot be read.")
        case .leaf:
            break
        case .directory(let descriptor):
            guard let stream = fdopendir(descriptor) else {
                close(descriptor)
                throw CleanupFailure.rejected("This directory cannot be read.")
            }
            stack.append(DirectoryFrame(descriptor: descriptor, stream: stream, path: rootPath, metadata: root))
        }
        let rootDevice = UInt64(truncatingIfNeeded: root.st_dev)
        absorb(path: rootPath, name: nil, metadata: root, allocated: &allocated, logical: &logical, count: &count,
               newest: &newest, signature: &signature, shared: &shared, identities: &identities)
        // Keep only the active ancestry open, not every pending sibling. Wide cache
        // trees can otherwise exhaust macOS's descriptor limit before any descent.
        while let frame = stack.last {
            if count % 128 == 0 { try Task.checkCancellation() }
            errno = 0
            guard let entry = readdir(frame.stream) else {
                if errno != 0 { complete = false }
                var finalMetadata = stat()
                if fstat(frame.descriptor, &finalMetadata) != 0
                    || !sameDirectory(finalMetadata, frame.metadata) { complete = false }
                closedir(frame.stream)
                stack.removeLast()
                continue
            }
            guard let name = entryName(entry) else { complete = false; continue }
            if isDot(name) { continue }
            guard count < limit else { complete = false; break }
            var child = stat()
            guard fstatat(frame.descriptor, name, &child, AT_SYMLINK_NOFOLLOW) == 0 else {
                complete = false
                continue
            }
            guard UInt64(truncatingIfNeeded: child.st_dev) == rootDevice else {
                complete = false
                continue
            }
            let protected = isProtected(name)
            if protected { complete = false }
            absorb(path: frame.path, name: name, metadata: child, allocated: &allocated, logical: &logical,
                   count: &count, newest: &newest, signature: &signature, shared: &shared, identities: &identities)
            guard !protected, child.st_mode & S_IFMT == S_IFDIR else { continue }
            // Fail closed on exceptionally deep trees; never consume unbounded FDs.
            guard stack.count < 128 else { complete = false; continue }
            let descriptor = openat(frame.descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { complete = false; continue }
            var openedMetadata = stat()
            guard fstat(descriptor, &openedMetadata) == 0, sameDirectory(openedMetadata, child) else {
                close(descriptor)
                complete = false
                continue
            }
            guard let stream = fdopendir(descriptor) else {
                close(descriptor)
                complete = false
                continue
            }
            var childPath = frame.path
            if childPath.last != UInt8(ascii: "/") { childPath.append(UInt8(ascii: "/")) }
            childPath.append(contentsOf: nameBytes(name))
            stack.append(DirectoryFrame(descriptor: descriptor, stream: stream, path: childPath, metadata: openedMetadata))
        }
        return DiskSnapshot(identity: "\(root.st_dev):\(root.st_ino)", signature: signature,
                            allocatedBytes: allocated, logicalBytes: logical, entryCount: count,
                            newestModification: newest, complete: complete, hasSharedLinks: shared)
    }

    private enum OpenedRoot {
        case unsafe
        case unreadable
        case leaf
        case directory(Int32)
    }

    /// `lstat` distinguishes an unsafe symlink from a directory `open` cannot read.
    /// Non-directories are measured from that single `lstat` and are not walked.
    private static func openForMeasure(_ path: [UInt8], metadata: UnsafeMutablePointer<stat>) -> OpenedRoot {
        var terminated = path
        terminated.append(0)
        return terminated.withUnsafeBytes { raw -> OpenedRoot in
            guard let base = raw.baseAddress else { return .unsafe }
            return base.assumingMemoryBound(to: UInt8.self).withMemoryRebound(to: CChar.self, capacity: raw.count) { pointer in
                guard lstat(pointer, metadata) == 0 else { return .unsafe }
                let kind = metadata.pointee.st_mode & S_IFMT
                if kind == S_IFLNK { return .unsafe }
                if kind != S_IFDIR { return .leaf }
                let descriptor = open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard descriptor >= 0 else { return .unreadable }
                var opened = stat()
                guard fstat(descriptor, &opened) == 0, sameDirectory(opened, metadata.pointee) else {
                    close(descriptor)
                    return .unsafe
                }
                metadata.pointee = opened
                return .directory(descriptor)
            }
        }
    }

    #if canImport(Darwin)
    private typealias DirectoryStream = UnsafeMutablePointer<DIR>
    #else
    private typealias DirectoryStream = OpaquePointer
    #endif

    private struct DirectoryFrame {
        let descriptor: Int32
        let stream: DirectoryStream
        let path: [UInt8]
        let metadata: stat
    }

    /// Confirm the descriptor still identifies the directory we statted, on the
    /// same device. A replaced directory or newly mounted volume is not traversed.
    private static func sameDirectory(_ actual: stat, _ expected: stat) -> Bool {
        guard actual.st_mode & S_IFMT == S_IFDIR,
              actual.st_dev == expected.st_dev, actual.st_ino == expected.st_ino,
              actual.st_mode == expected.st_mode else { return false }
        #if canImport(Darwin)
        return actual.st_mtimespec.tv_sec == expected.st_mtimespec.tv_sec
            && actual.st_mtimespec.tv_nsec == expected.st_mtimespec.tv_nsec
            && actual.st_ctimespec.tv_sec == expected.st_ctimespec.tv_sec
            && actual.st_ctimespec.tv_nsec == expected.st_ctimespec.tv_nsec
        #else
        return actual.st_mtim.tv_sec == expected.st_mtim.tv_sec
            && actual.st_mtim.tv_nsec == expected.st_mtim.tv_nsec
            && actual.st_ctim.tv_sec == expected.st_ctim.tv_sec
            && actual.st_ctim.tv_nsec == expected.st_ctim.tv_nsec
        #endif
    }

    private struct Identity: Hashable {
        var device: UInt64
        var inode: UInt64
    }

    private static let protectedExact: [[UInt8]] = [".git", ".env", "credentials", "auth.json"].map { Array($0.utf8) }
    private static let protectedPrefixes: [[UInt8]] = [".env."].map { Array($0.utf8) }
    private static let protectedSuffixes: [[UInt8]] = [".p12", ".mobileprovision", ".xcarchive", ".keychain-db"].map { Array($0.utf8) }

    private static func absorb(path: [UInt8], name: UnsafePointer<CChar>?, metadata: stat, allocated: inout Int64,
                               logical: inout Int64, count: inout Int, newest: inout Date, signature: inout UInt64,
                               shared: inout Bool, identities: inout Set<Identity>) {
        count += 1
        let identity = Identity(device: UInt64(truncatingIfNeeded: metadata.st_dev), inode: UInt64(truncatingIfNeeded: metadata.st_ino))
        #if canImport(Darwin)
        let modified = metadata.st_mtimespec
        let changed = metadata.st_ctimespec
        #else
        let modified = metadata.st_mtim
        let changed = metadata.st_ctim
        #endif
        let date = Date(timeIntervalSince1970: Double(modified.tv_sec) + Double(modified.tv_nsec) / 1e9)
        newest = max(newest, date)
        var hash: UInt64 = 14695981039346656037
        hashBytes(&hash, path)
        if let name {
            if path.last != UInt8(ascii: "/") { hashByte(&hash, UInt8(ascii: "/")) }
            var cursor = name
            while cursor.pointee != 0 {
                hashByte(&hash, UInt8(bitPattern: cursor.pointee))
                cursor = cursor.advanced(by: 1)
            }
        }
        hashByte(&hash, UInt8(ascii: "|"))
        hashInteger(&hash, metadata.st_dev)
        hashByte(&hash, UInt8(ascii: ":"))
        hashInteger(&hash, metadata.st_ino)
        hashByte(&hash, UInt8(ascii: "|"))
        hashInteger(&hash, metadata.st_mode)
        hashByte(&hash, UInt8(ascii: "|"))
        hashInteger(&hash, metadata.st_size)
        hashByte(&hash, UInt8(ascii: "|"))
        hashInteger(&hash, modified.tv_sec)
        hashByte(&hash, UInt8(ascii: ":"))
        hashInteger(&hash, modified.tv_nsec)
        hashByte(&hash, UInt8(ascii: "|"))
        hashInteger(&hash, changed.tv_sec)
        hashByte(&hash, UInt8(ascii: ":"))
        hashInteger(&hash, changed.tv_nsec)
        signature ^= hash
        if identities.insert(identity).inserted {
            logical += max(0, Int64(metadata.st_size))
            if metadata.st_mode & S_IFMT == S_IFREG && metadata.st_nlink > 1 {
                shared = true
            } else {
                allocated += max(0, Int64(metadata.st_blocks)) * 512
            }
        }
    }

    private static func fileSystemBytes(_ url: URL) -> [UInt8] {
        url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return Array(url.path.utf8) }
            let start = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: start, count: strlen(pointer)))
        }
    }

    private static func entryName(_ entry: UnsafeMutablePointer<dirent>) -> UnsafePointer<CChar>? {
        guard let offset = MemoryLayout<dirent>.offset(of: \.d_name) else { return nil }
        return UnsafeRawPointer(entry).advanced(by: offset).assumingMemoryBound(to: CChar.self)
    }

    private static func isDot(_ name: UnsafePointer<CChar>) -> Bool {
        name[0] == 46 && (name[1] == 0 || (name[1] == 46 && name[2] == 0))
    }

    private static func nameBytes(_ name: UnsafePointer<CChar>) -> [UInt8] {
        var bytes: [UInt8] = []
        var cursor = name
        while cursor.pointee != 0 {
            bytes.append(UInt8(bitPattern: cursor.pointee))
            cursor = cursor.advanced(by: 1)
        }
        return bytes
    }

    private static func isProtected(_ name: UnsafePointer<CChar>) -> Bool {
        protectedExact.contains { equals(name, $0) }
            || protectedPrefixes.contains { hasPrefix(name, $0) }
            || protectedSuffixes.contains { hasSuffix(name, $0) }
    }

    private static func equals(_ name: UnsafePointer<CChar>, _ literal: [UInt8]) -> Bool {
        for (index, byte) in literal.enumerated() {
            let value = folded(name[index])
            if value == 0 || value != byte { return false }
        }
        return name[literal.count] == 0
    }

    private static func hasPrefix(_ name: UnsafePointer<CChar>, _ prefix: [UInt8]) -> Bool {
        for (index, byte) in prefix.enumerated() {
            if folded(name[index]) != byte { return false }
        }
        return true
    }

    private static func hasSuffix(_ name: UnsafePointer<CChar>, _ suffix: [UInt8]) -> Bool {
        var length = 0
        while name[length] != 0 { length += 1 }
        guard length >= suffix.count else { return false }
        let start = length - suffix.count
        for (offset, byte) in suffix.enumerated() {
            if folded(name[start + offset]) != byte { return false }
        }
        return true
    }

    private static func folded(_ byte: CChar) -> UInt8 {
        let value = UInt8(bitPattern: byte)
        return value >= 65 && value <= 90 ? value + 32 : value
    }

    private static func hashBytes(_ hash: inout UInt64, _ bytes: [UInt8]) {
        for byte in bytes { hashByte(&hash, byte) }
    }

    private static func hashByte(_ hash: inout UInt64, _ byte: UInt8) {
        hash = (hash ^ UInt64(byte)) &* 1099511628211
    }

    private static func hashInteger<T: BinaryInteger>(_ hash: inout UInt64, _ value: T) {
        if value < (0 as T) {
            hashByte(&hash, UInt8(ascii: "-"))
        }
        hashUnsigned(&hash, UInt64(truncatingIfNeeded: value.magnitude))
    }

    private static func hashUnsigned(_ hash: inout UInt64, _ value: UInt64) {
        if value == 0 {
            hashByte(&hash, UInt8(ascii: "0"))
            return
        }
        // UInt64 needs at most 20 digits. Unlike InlineArray, this supports macOS 14.
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 20) { digits in
            var remainder = value
            var index = digits.count
            while remainder > 0 {
                index -= 1
                digits[index] = UInt8(ascii: "0") + UInt8(remainder % 10)
                remainder /= 10
            }
            while index < digits.count {
                hashByte(&hash, digits[index])
                index += 1
            }
        }
    }
}
