import SwiftUI

private enum DiskOddsStyle {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.095)
    static let panel = Color(red: 0.085, green: 0.11, blue: 0.135)
    static let mint = Color(red: 0.46, green: 0.91, blue: 0.76)
    static let amber = Color(red: 0.98, green: 0.73, blue: 0.39)
    static func odds(_ item: CleanupItem) -> Color {
        if item.action == .guide { return Color(red: 0.63, green: 0.64, blue: 0.81) }
        return item.odds >= 95 ? mint : amber
    }
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
    }
}

struct DiskOddsWorkspaceView: View {
    @Binding var mode: Int
    @StateObject private var cleanup = DeveloperCleanupModel()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(DiskOddsStyle.mint)
                Text("DiskOdds").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("MAKE ROOM TO BUILD").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker("Workspace", selection: $mode) {
                    Text("Developer cleanup").tag(0)
                    Text("Disk explorer").tag(1)
                }.pickerStyle(.segmented).frame(width: 310)
                Spacer()
                Label("On-device", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            if mode == 0 { DeveloperCleanupView(model: cleanup) }
            else { ContentView() }
        }
    }
}

struct DeveloperCleanupView: View {
    @ObservedObject var model: DeveloperCleanupModel
    var body: some View {
        VStack(spacing: 0) {
            if model.isDemo {
                Text("DESIGN PREVIEW · Illustrative 256 GB Mac · No files are scanned or deleted")
                    .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(8).background(DiskOddsStyle.amber.opacity(0.15))
            }
            HStack(spacing: 0) {
                sidebar.frame(width: 188)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        if let error = model.error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(DiskOddsStyle.amber).font(.callout).textSelection(.enabled)
                        }
                        if model.hasScanned {
                            summary
                            diskMap
                            candidates
                            warnings
                        } else { introduction }
                    }.padding(28)
                }.frame(maxWidth: .infinity)
                Divider()
                inspector.frame(width: 290)
            }
            Divider()
            footer
        }
        .background(DiskOddsStyle.background).foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showReview) { CleanupReviewSheet(model: model) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORKSPACE").font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.bottom, 8)
            categoryButton(nil, title: "All opportunities", symbol: "square.grid.2x2")
            ForEach(CleanupCategory.allCases) { category in
                categoryButton(category, title: category.title, symbol: category.symbol)
            }
            Divider().padding(.vertical, 12)
            Text("PROJECT FOLDERS").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Button(action: model.addProjectFolder) { Label("Add folder…", systemImage: "folder.badge.plus") }
                .buttonStyle(.plain).foregroundStyle(DiskOddsStyle.mint).disabled(model.scanning || model.cleaning || model.isDemo)
            ForEach(model.projectRoots, id: \.self) { path in
                HStack {
                    Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).lineLimit(1).help(path)
                    Spacer()
                    Button { model.removeProjectFolder(path) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain).accessibilityLabel("Remove \(path) from scan scope")
                        .disabled(model.scanning || model.cleaning || model.isDemo)
                }
            }
            Text("Add project folders to find ignored framework caches. Your repositories stay intact.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
            Label("Protected by default", systemImage: "shield.lefthalf.filled")
                .foregroundStyle(DiskOddsStyle.mint).font(.caption.weight(.semibold))
            Text("Source code, Git history, signing keys, archives, agent conversations, and shared model blobs are not bulk-cleaned.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Trash in Finder", action: model.openTrash).font(.caption).buttonStyle(.plain).padding(.top, 10)
        }.padding(20).frame(maxHeight: .infinity, alignment: .topLeading)
    }
    private func categoryButton(_ category: CleanupCategory?, title: String, symbol: String) -> some View {
        Button { model.category = category } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }.padding(.vertical, 10).padding(.horizontal, 8)
                .background(model.category == category ? DiskOddsStyle.mint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(model.category == category ? DiskOddsStyle.mint : Color.secondary)
        }.buttonStyle(.plain)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LESS DISK ANXIETY. MORE SHIPPING.").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(DiskOddsStyle.mint)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Room for your next idea.").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Find the leftovers. Understand the odds. Keep what matters.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.scanning {
                    Button("Cancel scan", action: model.cancelScan).buttonStyle(.bordered)
                } else {
                    Button(action: model.scan) {
                        Label(model.hasScanned ? "Rescan" : "Scan developer storage", systemImage: "arrow.triangle.2.circlepath")
                    }.buttonStyle(.borderedProminent).tint(DiskOddsStyle.mint).foregroundStyle(.black)
                        .disabled(model.cleaning || model.isDemo)
                }
            }
            if model.scanning {
                HStack { ProgressView().controlSize(.small); Text("Reading developer folders and simulator metadata… Nothing is being deleted.").font(.caption) }
            }
        }
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "internaldrive.fill").font(.system(size: 55)).foregroundStyle(DiskOddsStyle.mint)
            Text("Your Mac should run your ideas,\nnot store every old build.").font(.title2.weight(.semibold))
            Text("Scan Xcode build leftovers, unavailable simulators, package caches, and local model stores. Each result shows its footprint, cleanup confidence, consequences, and recovery path.")
                .foregroundStyle(.secondary)
            Text("Nothing is preselected. Most cleanups move files to Trash. Simulator deletion requires a separate, permanent-data-loss confirmation.")
                .foregroundStyle(DiskOddsStyle.mint)
            Text(CleanupPolicy.disclaimer).font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(DiskOddsStyle.panel, in: RoundedRectangle(cornerRadius: 16))
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                metric("HIGH-CONFIDENCE CANDIDATES", value: DiskOddsStyle.bytes(model.quickWinBytes), detail: "95%+ · review before removal", accent: true)
                metric("DEVELOPER FOOTPRINT", value: DiskOddsStyle.bytes(model.inventoryBytes), detail: "Across scanned locations")
                metric("HOME VOLUME FREE", value: model.report.capacity > 0 ? DiskOddsStyle.bytes(model.report.freeBytes) : "Unknown", detail: "Actual available space")
            }
            if model.report.capacity > 0 {
                GeometryReader { geometry in
                    let ratio = min(1, max(0, Double(model.report.capacity - model.report.freeBytes) / Double(model.report.capacity)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(DiskOddsStyle.mint.opacity(0.75))
                        Capsule().fill(Color.white.opacity(0.25)).frame(width: geometry.size.width * ratio)
                    }
                }.frame(height: 8)
                HStack {
                    Text("Home volume · \(DiskOddsStyle.bytes(model.report.capacity - model.report.freeBytes)) used")
                    Spacer()
                    Text("\(DiskOddsStyle.bytes(model.report.capacity)) capacity")
                }.font(.caption).foregroundStyle(.secondary)
            }
            Text("Footprint is not guaranteed reclaim. APFS clones, snapshots, shared files, and Trash affect the space actually freed.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(DiskOddsStyle.panel, in: RoundedRectangle(cornerRadius: 14))
    }
    private func metric(_ title: String, value: String, detail: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(accent ? DiskOddsStyle.mint : Color.white)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var diskMap: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Where your space went").font(.headline)
                Spacer()
                Text("Largest \(min(12, model.visible.count)) matches · area = footprint").font(.caption).foregroundStyle(.secondary)
            }
            if model.visible.isEmpty {
                Text(model.report.items.isEmpty ? "No supported leftovers found in the readable locations. Check scan warnings or add project folders." : "No matches for this filter.")
                    .foregroundStyle(.secondary).padding(24)
            } else {
                GeometryReader { geometry in
                    let tiles = CleanupMapLayout.tiles(Array(model.visible.prefix(12)), rect: CGRect(origin: .zero, size: geometry.size))
                    ForEach(tiles) { tile in
                        Button { model.focusedID = tile.item.id } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if tile.rect.height > 48 && tile.rect.width > 100 {
                                    Text(tile.item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                }
                                if tile.rect.width > 62 && tile.rect.height > 30 {
                                    Text(DiskOddsStyle.bytes(tile.item.snapshot.allocatedBytes)).font(.system(size: 20, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                if tile.rect.height > 76 && tile.rect.width > 100 {
                                    Text("\(tile.item.odds)% odds · \(tile.item.action == .guide ? "manage in app" : "review")").font(.caption)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(tile.rect.width > 80 ? 12 : 3)
                                .background(DiskOddsStyle.odds(tile.item).opacity(model.focusedID == tile.item.id ? 0.35 : 0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DiskOddsStyle.odds(tile.item).opacity(model.focusedID == tile.item.id ? 0.9 : 0.15)))
                        }.buttonStyle(.plain)
                            .frame(width: max(0, tile.rect.width - 4), height: max(0, tile.rect.height - 4)).clipped()
                            .position(x: tile.rect.midX, y: tile.rect.midY)
                            .help("\(tile.item.title) · \(DiskOddsStyle.bytes(tile.item.snapshot.allocatedBytes)) · \(tile.item.odds)% heuristic confidence")
                            .accessibilityLabel("\(tile.item.title), \(DiskOddsStyle.bytes(tile.item.snapshot.allocatedBytes)), \(tile.item.odds) percent cleanup confidence. Inspect item.")
                    }
                }.frame(height: 210)
            }
            HStack(spacing: 18) {
                Label("95%+ confidence", systemImage: "circle.fill").foregroundStyle(DiskOddsStyle.mint)
                Label("Review trade-offs", systemImage: "circle.fill").foregroundStyle(DiskOddsStyle.amber)
                Label("Managed / keep", systemImage: "circle.fill").foregroundStyle(Color(red: 0.63, green: 0.64, blue: 0.81))
            }.font(.caption)
        }
    }
    private var candidates: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cleanup opportunities").font(.headline)
                Spacer()
                Toggle("Highest odds first", isOn: $model.highestOddsFirst).toggleStyle(.checkbox).font(.caption)
            }
            TextField("Filter by project, tool, or path", text: $model.search).textFieldStyle(.roundedBorder).font(.body)
            LazyVStack(spacing: 6) {
                ForEach(model.visible) { item in
                    HStack(spacing: 12) {
                        Toggle("Select \(item.title)", isOn: Binding(get: { model.selected.contains(item.id) }, set: { _ in model.toggleSelection(item) }))
                            .labelsHidden().toggleStyle(.checkbox).disabled(!item.actionable || model.isKept(item) || model.scanning || model.cleaning)
                        Button { model.focusedID = item.id } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.category.symbol).foregroundStyle(DiskOddsStyle.odds(item)).frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                    Text(model.isKept(item) ? "Kept · excluded from cleanup" : (item.blocker ?? (item.action == .guide ? "Manage with owning app" : item.reasons.first ?? "Review item")))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(DiskOddsStyle.bytes(item.snapshot.allocatedBytes)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                Text("\(item.odds)%").font(.system(size: 13, weight: .bold)).foregroundStyle(DiskOddsStyle.odds(item))
                                    .padding(.horizontal, 9).padding(.vertical, 6).background(DiskOddsStyle.odds(item).opacity(0.13), in: Capsule())
                            }
                        }.buttonStyle(.plain)
                    }.padding(12).background(model.focusedID == item.id ? Color.white.opacity(0.075) : DiskOddsStyle.panel, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text(CleanupPolicy.disclaimer).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var warnings: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.report.warnings.isEmpty {
                DisclosureGroup("\(model.report.warnings.count) scan warnings · coverage may be incomplete") {
                    ForEach(Array(model.report.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                    }
                }.foregroundStyle(DiskOddsStyle.amber)
            }
            if !model.receipts.isEmpty {
                DisclosureGroup("Recent cleanup history") {
                    ForEach(model.receipts.prefix(8)) { receipt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: receipt.originalPath).lastPathComponent).font(.callout.weight(.medium))
                            Text(receipt.message).font(.caption).foregroundStyle(receipt.succeeded ? Color.secondary : DiskOddsStyle.amber)
                            Text(receipt.date.formatted()).font(.caption2).foregroundStyle(.secondary)
                            if let trash = receipt.trashPath { Button("Show in Trash") { model.reveal(trash) }.font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                }
            }
        }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("THE REASONING").font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                if let item = model.focused {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(item.odds)%").font(.system(size: 54, weight: .medium, design: .rounded)).foregroundStyle(DiskOddsStyle.odds(item))
                        Text("Cleanup confidence").font(.headline)
                        Text("Heuristic, not a guarantee").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(item.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    detail("WHY THESE ODDS", text: item.reasons.joined(separator: "\n\n"))
                    detail("WHAT CHANGES", text: item.impact)
                    detail("HOW TO RECOVER", text: item.recovery)
                    if let blocker = item.blocker { Label(blocker, systemImage: "lock.fill").foregroundStyle(DiskOddsStyle.amber).font(.callout) }
                    Button("Reveal in Finder") { model.reveal(item.path) }.buttonStyle(.bordered).disabled(model.isDemo)
                    Button(model.isKept(item) ? "Remove keep rule" : "Keep this item") { model.keep(item) }
                        .buttonStyle(.bordered).disabled(model.cleaning || model.scanning || model.isDemo)
                    if item.action == .deleteSimulator {
                        Text("Uses simctl delete with this exact UUID—not a blanket delete unavailable command.").font(.caption).foregroundStyle(DiskOddsStyle.amber)
                    }
                } else {
                    Image(systemName: "shield.checkered").font(.system(size: 45)).foregroundStyle(DiskOddsStyle.mint)
                    Text("Evidence before deletion.").font(.title3.weight(.semibold))
                    Text("Select a tile or row to understand what it is, why it is a candidate, and what happens next.").foregroundStyle(.secondary)
                    detail("NOT A MAGIC PERCENTAGE", text: CleanupPolicy.disclaimer)
                    detail("YOUR CHOICE, EVERY TIME", text: "No automatic deletion. No blanket simulator reset. No clearing agent conversations or shared model blobs.")
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func detail(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            Text(text).font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Image(systemName: model.cleaning ? "hourglass" : "checkmark.shield").foregroundStyle(DiskOddsStyle.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.cleaning ? "Revalidating and applying your plan…" : "\(model.selectedItems.count) selected · \(DiskOddsStyle.bytes(model.selectedBytes)) estimated footprint")
                    .font(.system(size: 14, weight: .semibold))
                Text("Trash is recoverable until emptied. Simulator deletion is permanent.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Select 95%+ candidates", action: model.selectQuickWins).buttonStyle(.bordered)
                .disabled(model.quickWins.isEmpty || model.scanning || model.cleaning)
            Button("Review cleanup…") { model.showReview = true }.buttonStyle(.borderedProminent)
                .tint(DiskOddsStyle.mint).foregroundStyle(.black)
                .disabled(model.selectedItems.isEmpty || model.scanning || model.cleaning || model.isDemo)
        }.padding(.horizontal, 24).padding(.vertical, 15).background(DiskOddsStyle.panel)
    }
}

private struct CleanupMapTile: Identifiable {
    var id: String { item.id }
    let item: CleanupItem
    let rect: CGRect
}
private enum CleanupMapLayout {
    static func tiles(_ items: [CleanupItem], rect: CGRect) -> [CleanupMapTile] {
        guard !items.isEmpty else { return [] }
        if items.count == 1 { return [CleanupMapTile(item: items[0], rect: rect)] }
        let total = items.reduce(0.0) { $0 + Double(max(1, $1.snapshot.allocatedBytes)) }
        var partial = 0.0
        var split = 1
        for index in 0..<(items.count - 1) {
            partial += Double(max(1, items[index].snapshot.allocatedBytes))
            split = index + 1
            if partial >= total / 2 { break }
        }
        let ratio = partial / total
        let first: CGRect
        let second: CGRect
        if rect.width >= rect.height {
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width * ratio, height: rect.height)
            second = CGRect(x: first.maxX, y: rect.minY, width: rect.width - first.width, height: rect.height)
        } else {
            first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * ratio)
            second = CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: rect.height - first.height)
        }
        return tiles(Array(items.prefix(split)), rect: first) + tiles(Array(items.dropFirst(split)), rect: second)
    }
}

private struct CleanupReviewSheet: View {
    @ObservedObject var model: DeveloperCleanupModel
    @State private var acknowledged = false
    @State private var simulatorConfirmation = ""
    private var hasSimulator: Bool { model.selectedItems.contains { $0.action == .deleteSimulator } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review before making room").font(.title2.weight(.semibold))
            Text("\(model.selectedItems.count) items · \(DiskOddsStyle.bytes(model.selectedBytes)) estimated footprint").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.selectedItems) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.title).font(.headline)
                                Spacer()
                                Text(item.action == .trash ? "MOVE TO TRASH" : "DELETE PERMANENTLY")
                                    .font(.caption.weight(.bold)).foregroundStyle(item.action == .trash ? DiskOddsStyle.mint : DiskOddsStyle.amber)
                            }
                            Text(item.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            Text(item.impact).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }.frame(maxHeight: 300)
            Text("Close Xcode, simulators, dev servers, package managers, and coding agents first. Files and simulator state are checked again immediately before cleanup. Process checks are conservative, not proof that no other app uses a file.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Toggle("I reviewed the paths, closed development tasks, and understand the recovery costs.", isOn: $acknowledged).toggleStyle(.checkbox)
            if hasSimulator {
                Text("Simulator app data cannot be restored from Trash. Type DELETE to confirm.").foregroundStyle(DiskOddsStyle.amber)
                TextField("DELETE", text: $simulatorConfirmation).textFieldStyle(.roundedBorder)
            }
            Text("Moving to Trash does not free space immediately. Empty Trash yourself in Finder only after confirming your projects still work.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.showReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(hasSimulator ? "Apply reviewed cleanup" : "Move selected items to Trash") {
                    model.clean(acknowledged: acknowledged, simulatorConfirmation: simulatorConfirmation)
                }.buttonStyle(.borderedProminent).tint(hasSimulator ? DiskOddsStyle.amber : DiskOddsStyle.mint).foregroundStyle(.black)
                    .disabled(!acknowledged || (hasSimulator && simulatorConfirmation != "DELETE") || model.isDemo)
            }
        }.padding(28).frame(width: 680).preferredColorScheme(.dark)
    }
}
