import Foundation

// These are rule-based confidence scores, not calibrated probabilities.
nonisolated enum CleanupCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case builds, simulators, caches, models
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builds: "Build leftovers"
        case .simulators: "Simulators"
        case .caches: "Developer caches"
        case .models: "Local AI models"
        }
    }
    var symbol: String {
        switch self {
        case .builds: "hammer.fill"
        case .simulators: "iphone.gen3"
        case .caches: "shippingbox.fill"
        case .models: "brain"
        }
    }
}

nonisolated enum CleanupKind: String, Codable, Sendable {
    case derivedBuild, xcodeCache, packageCache, projectCache
    case unavailableSimulator, availableSimulator, runtime, modelStore
    var category: CleanupCategory {
        switch self {
        case .derivedBuild, .projectCache: .builds
        case .xcodeCache, .packageCache: .caches
        case .unavailableSimulator, .availableSimulator, .runtime: .simulators
        case .modelStore: .models
        }
    }
}

nonisolated enum CleanupAction: String, Codable, Sendable {
    case trash, deleteSimulator, guide
}

nonisolated struct DiskSnapshot: Codable, Sendable, Equatable {
    let identity: String
    let signature: UInt64
    let allocatedBytes: Int64
    let logicalBytes: Int64
    let entryCount: Int
    let newestModification: Date
    let complete: Bool
    let hasSharedLinks: Bool
}

nonisolated struct CleanupItem: Identifiable, Codable, Sendable {
    var id: String { path }
    let path: String
    let title: String
    let kind: CleanupKind
    let snapshot: DiskSnapshot
    let action: CleanupAction
    let odds: Int
    let reasons: [String]
    let impact: String
    let recovery: String
    let blocker: String?
    var projectRoot: String? = nil
    var simulatorID: String? = nil
    var category: CleanupCategory { kind.category }
    var actionable: Bool { action != .guide && blocker == nil && snapshot.complete }
    var quickWin: Bool { actionable && action == .trash && odds >= 95 }
}

nonisolated struct CleanupContext: Sendable {
    let home: URL
    let projectRoots: [URL]
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, projectRoots: [URL] = []) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
        self.projectRoots = projectRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    }
}

nonisolated struct CleanupReport: Sendable {
    var items: [CleanupItem] = []
    var warnings: [String] = []
    var scannedAt: Date = .now
    var capacity: Int64 = 0
    var freeBytes: Int64 = 0
}

nonisolated struct CleanupReceipt: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let originalPath: String
    let trashPath: String?
    let stagedBytes: Int64
    let message: String
    let succeeded: Bool
}

nonisolated enum CleanupFailure: LocalizedError {
    case rejected(String)
    var errorDescription: String? {
        switch self { case .rejected(let message): message }
    }
}

nonisolated enum CleanupPolicy {
    static let disclaimer = "Odds are heuristic cleanup confidence, not a measured probability or a guarantee. Modification dates are not proof of last use."
    static let cachePaths = [
        "Library/Caches/Homebrew", "Library/Caches/CocoaPods", "Library/Caches/pip",
        "Library/Caches/uv", "Library/Caches/org.swift.swiftpm", ".npm/_cacache"
    ]
    static let projectPaths = [
        ".next/cache", ".turbo", ".parcel-cache", "node_modules/.cache",
        ".build/xcode-derived-data/Build", ".build/xcode-derived-data/Index.noindex",
        ".derivedData/Build", ".derivedData/Index.noindex",
        "DerivedData/Build", "DerivedData/Index.noindex"
    ]
    static let derivedPaths = ["Build", "Index.noindex"]
    static let xcodeCaches = ["ModuleCache.noindex", "CompilationCache.noindex", "SDKStatCaches.noindex"]

    static func contains(_ root: String, _ path: String) -> Bool {
        let r = URL(fileURLWithPath: root).standardizedFileURL.pathComponents
        let p = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        return p.count > r.count && Array(p.prefix(r.count)) == r
    }

    static func overlaps(_ paths: [String]) -> Bool {
        let sorted = paths.sorted()
        for (index, path) in sorted.enumerated() {
            for other in sorted.dropFirst(index + 1) {
                if path == other || contains(path, other) || contains(other, path) { return true }
            }
        }
        return false
    }

    static func confidence(kind: CleanupKind, snapshot: DiskSnapshot, now: Date = .now) -> Int {
        guard snapshot.complete else { return 0 }
        let age = now.timeIntervalSince(snapshot.newestModification) / 86400
        switch kind {
        case .modelStore: return 40
        case .runtime: return 50
        case .availableSimulator: return 45
        case .unavailableSimulator: return 80
        case .projectCache: return age >= 7 ? 94 : 65
        case .derivedBuild, .xcodeCache: return age >= 7 ? 98 : 65
        case .packageCache: return age >= 7 ? 96 : 65
        }
    }

    static func allowsTrash(_ item: CleanupItem, context: CleanupContext) -> Bool {
        guard item.action == .trash, item.actionable else { return false }
        let home = context.home.path
        let derived = context.home.appendingPathComponent("Library/Developer/Xcode/DerivedData").path
        switch item.kind {
        case .packageCache:
            return cachePaths.contains { context.home.appendingPathComponent($0).path == item.path }
        case .xcodeCache:
            return xcodeCaches.contains { derived + "/" + $0 == item.path }
        case .derivedBuild:
            let url = URL(fileURLWithPath: item.path)
            return derivedPaths.contains(url.lastPathComponent)
                && url.deletingLastPathComponent().deletingLastPathComponent().path == derived
                && contains(home, item.path)
        case .projectCache:
            guard let project = item.projectRoot,
                  context.projectRoots.contains(where: { $0.path == project || contains($0.path, project) }) else { return false }
            return projectPaths.contains { project + "/" + $0 == item.path }
        default: return false
        }
    }

    static func uniqueItems(_ items: [CleanupItem]) -> [CleanupItem] {
        var selected: [CleanupItem] = []
        for item in items.sorted(by: { $0.path.count < $1.path.count }) {
            if !selected.contains(where: { $0.path == item.path || contains($0.path, item.path) }) {
                selected.append(item)
            }
        }
        return selected.sorted { $0.snapshot.allocatedBytes > $1.snapshot.allocatedBytes }
    }
}
