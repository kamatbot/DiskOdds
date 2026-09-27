import AppKit
import Combine
import Foundation

@MainActor
final class DeveloperCleanupModel: ObservableObject {
    @Published var report = CleanupReport()
    @Published var hasScanned = false
    @Published var scanning = false
    @Published var cleaning = false
    @Published var selected = Set<String>()
    @Published var focusedID: String?
    @Published var category: CleanupCategory?
    @Published var search = ""
    @Published var highestOddsFirst = false
    @Published var showReview = false
    @Published var error: String?
    @Published var projectRoots: [String]
    @Published var keptPaths: Set<String>
    @Published var receipts: [CleanupReceipt]
    let isDemo = ProcessInfo.processInfo.arguments.contains("--diskodds-demo")
    private let executor = CleanupExecutor()
    private var scanTask: Task<CleanupReport, Error>?
    private var generation = UUID()
    private let defaults = UserDefaults.standard

    init() {
        projectRoots = UserDefaults.standard.stringArray(forKey: "diskodds.projects.v1") ?? []
        keptPaths = Set(UserDefaults.standard.stringArray(forKey: "diskodds.keep.v1") ?? [])
        receipts = (UserDefaults.standard.data(forKey: "diskodds.receipts.v1").flatMap {
            try? JSONDecoder().decode([CleanupReceipt].self, from: $0)
        }) ?? []
        if isDemo {
            report = Self.demoReport()
            hasScanned = true
            focusedID = report.items.first?.id
        }
    }

    var context: CleanupContext { CleanupContext(projectRoots: projectRoots.map { URL(fileURLWithPath: $0) }) }
    var focused: CleanupItem? { report.items.first { $0.id == focusedID } }
    var visible: [CleanupItem] {
        report.items.filter {
            (category == nil || $0.category == category) &&
            (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search))
        }.sorted {
            if highestOddsFirst && $0.odds != $1.odds { return $0.odds > $1.odds }
            return $0.snapshot.allocatedBytes > $1.snapshot.allocatedBytes
        }
    }
    var quickWins: [CleanupItem] { report.items.filter { $0.quickWin && !isKept($0) } }
    var selectedItems: [CleanupItem] { report.items.filter { selected.contains($0.id) && $0.actionable && !isKept($0) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.snapshot.allocatedBytes } }
    var quickWinBytes: Int64 { quickWins.reduce(0) { $0 + $1.snapshot.allocatedBytes } }
    var inventoryBytes: Int64 { report.items.reduce(0) { $0 + $1.snapshot.allocatedBytes } }

    func isKept(_ item: CleanupItem) -> Bool {
        keptPaths.contains { $0 == item.path || CleanupPolicy.contains($0, item.path) }
    }
    func toggleSelection(_ item: CleanupItem) {
        guard item.actionable, !isKept(item), !scanning, !cleaning else { return }
        if !selected.insert(item.id).inserted { selected.remove(item.id) }
    }
    func keep(_ item: CleanupItem) {
        if keptPaths.contains(item.path) { keptPaths.remove(item.path) } else { keptPaths.insert(item.path) }
        selected.remove(item.id)
        defaults.set(keptPaths.sorted(), forKey: "diskodds.keep.v1")
    }
    func selectQuickWins() { selected = Set(quickWins.map(\.id)) }

    func scan() {
        guard !cleaning, !isDemo else { return }
        scanTask?.cancel()
        let token = UUID()
        generation = token
        let context = context
        scanning = true
        selected.removeAll()
        error = nil
        let worker = Task.detached(priority: .utility) { try CleanupScanner().scan(context: context) }
        scanTask = worker
        Task {
            do {
                let result = try await worker.value
                guard generation == token else { return }
                report = result
                hasScanned = true
                focusedID = result.items.first?.id
            } catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { scanning = false; scanTask = nil }
        }
    }
    func cancelScan() {
        generation = UUID()
        scanTask?.cancel()
        scanTask = nil
        scanning = false
    }
    func addProjectFolder() {
        guard !scanning, !cleaning, !isDemo else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder containing your coding projects"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            projectRoots = Array(Set(projectRoots + panel.urls.map { $0.resolvingSymlinksInPath().path })).sorted()
            defaults.set(projectRoots, forKey: "diskodds.projects.v1")
            scan()
        }
    }
    func removeProjectFolder(_ path: String) {
        guard !scanning, !cleaning else { return }
        projectRoots.removeAll { $0 == path }
        defaults.set(projectRoots, forKey: "diskodds.projects.v1")
        scan()
    }
    func clean(acknowledged: Bool, simulatorConfirmation: String) {
        guard !cleaning, !scanning, !isDemo else { return }
        let items = selectedItems
        let context = context
        let kept = keptPaths
        cleaning = true
        showReview = false
        error = nil
        Task {
            do {
                let result = try await executor.execute(items: items, context: context, keptPaths: kept,
                    acknowledged: acknowledged, simulatorConfirmation: simulatorConfirmation)
                receipts = Array((Array(result.reversed()) + receipts).prefix(40))
                if let data = try? JSONEncoder().encode(receipts) { defaults.set(data, forKey: "diskodds.receipts.v1") }
                let successes = Set(result.filter(\.succeeded).map(\.originalPath))
                report.items.removeAll { successes.contains($0.path) }
                selected.removeAll()
                if let failure = result.first(where: { !$0.succeeded }) { error = failure.message }
            } catch { self.error = error.localizedDescription }
            let cleanupError = error
            cleaning = false
            scan()
            error = cleanupError
        }
    }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func openTrash() { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) }

    private static func demoReport() -> CleanupReport {
        let gb: Int64 = 1_000_000_000
        let entries: [(String, String, CleanupKind, Int64, Int, CleanupAction)] = [
            ("~/Library/Developer/Xcode/DerivedData/Launchpad/Build", "Launchpad / old builds", .derivedBuild, 18 * gb, 98, .trash),
            ("~/Library/Developer/Xcode/DerivedData/Prototype/Index.noindex", "Prototype / index", .derivedBuild, 8 * gb, 98, .trash),
            ("~/.ollama/models", "Ollama model store", .modelStore, 22 * gb, 40, .guide),
            ("~/Library/Developer/CoreSimulator/Devices/example", "iPhone 15 · unavailable", .unavailableSimulator, 11 * gb, 80, .deleteSimulator),
            ("~/Library/Caches/Homebrew", "Homebrew downloads", .packageCache, 6 * gb, 96, .trash),
            ("~/.cache/huggingface/hub", "Hugging Face model store", .modelStore, 9 * gb, 40, .guide)
        ]
        var report = CleanupReport(capacity: 256 * gb, freeBytes: 12 * gb)
        report.items = entries.map { path, title, kind, bytes, odds, action in
            CleanupItem(path: path, title: title, kind: kind,
                snapshot: DiskSnapshot(identity: "demo", signature: 0, allocatedBytes: bytes, logicalBytes: bytes,
                                       entryCount: 1200, newestModification: .now.addingTimeInterval(-30 * 86400), complete: true, hasSharedLinks: false),
                action: action, odds: odds, reasons: ["Illustrative demo data, not a scan of this Mac.", "In a live scan, confidence uses the rule, complete metadata, and recent changes."],
                impact: "Review the owning tool and recovery cost before removing anything.",
                recovery: action == .trash ? "Restore from Trash or rebuild. Space is not freed until Trash is emptied." : "Use the owning application's manager and preserve unique data.", blocker: nil)
        }
        return report
    }
}
