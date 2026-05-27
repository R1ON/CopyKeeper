import Foundation
import Combine
import AppKit
import SwiftUI

enum GroupEditorMode: Equatable {
    case create
    case rename(UUID)
}

class ClipboardStore: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var groups: [ClipboardGroup] = []
    @Published var selectedGroupID: UUID?
    @Published var searchText: String = ""
    @Published var focusedItemID: UUID?
    // Not @Published: only read in the keyboard handler, never in a view body.
    // Publishing it would re-render the whole panel on every hover.
    var hoveredItemID: UUID?
    @Published var editingItemID: UUID?
    @Published var renamingItemID: UUID?
    @Published var groupEditorMode: GroupEditorMode?

    var activeColor: Color {
        if let id = selectedGroupID, let idx = groups.firstIndex(where: { $0.id == id }) {
            return GroupBarView.color(for: groups[idx], fallbackIndex: idx)
        }
        if let idx = groups.firstIndex(where: { $0.isDefault }) {
            return GroupBarView.color(for: groups[idx], fallbackIndex: idx)
        }
        return GroupBarView.palette[0]
    }

    // Loaded once; playing a fresh NSSound from disk on every copy is wasteful.
    private static let copySound = NSSound(named: "Frog")

    /// Set right before the app writes to the pasteboard itself, so the
    /// monitor skips capturing our own copy as a new (duplicate) item.
    var ignoreNextChange = false

    var persistence = PersistenceManager()

    // Coalesce rapid mutations into a single off-main write.
    private var saveWorkItem: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.copykeeper.save", qos: .utility)

    private let totalCopiedKey = "com.copykeeper.totalCopied"
    private let firstLaunchKey = "com.copykeeper.firstLaunch"
    private let retentionMigratedKey = "com.copykeeper.retentionDefaultMigrated.v2"

    var totalCopied: Int {
        UserDefaults.standard.integer(forKey: totalCopiedKey)
    }

    var firstLaunchDate: Date {
        if let date = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date {
            return date
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: firstLaunchKey)
        return now
    }

    func cacheSizeBytes() -> Int64 {
        persistence.cacheSizeBytes()
    }

    func sizeBytes(for item: ClipboardItem) -> Int64 {
        var total = Int64(item.textContent?.utf8.count ?? 0)
        if let path = item.imagePath {
            total += persistence.fileSize(atPath: path)
        }
        if let preview = item.previewImagePath {
            total += persistence.fileSize(atPath: preview)
        }
        return total
    }

    func groupSizeBytes(_ group: ClipboardGroup) -> Int64 {
        let ids = Set(group.itemIDs)
        return items.filter { ids.contains($0.id) }
            .reduce(0) { $0 + sizeBytes(for: $1) }
    }

    init() {
        _ = firstLaunchDate
        if let data = persistence.load() {
            items = data.items
            groups = data.groups
        }
        if !groups.contains(where: { $0.isDefault }) {
            let defaultGroup = ClipboardGroup(name: "Все", retention: .oneWeek, isDefault: true)
            groups.insert(defaultGroup, at: 0)
            saveData()
        }
        migrateDefaultRetentionIfNeeded()
    }

    /// One-time retention default: the main ("Все") group keeps 1 week so
    /// history doesn't pile up forever; user-made groups stay unlimited.
    private func migrateDefaultRetentionIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: retentionMigratedKey) else { return }
        var changed = false
        for i in groups.indices {
            let target: RetentionPeriod = groups[i].isDefault ? .oneWeek : .never
            if groups[i].retention != target {
                groups[i].retention = target
                changed = true
            }
        }
        UserDefaults.standard.set(true, forKey: retentionMigratedKey)
        if changed { saveData() }
    }

    var allGroup: ClipboardGroup? {
        groups.first(where: { $0.isDefault })
    }

    var filteredItems: [ClipboardItem] {
        guard let selectedID = selectedGroupID,
              let group = groups.first(where: { $0.id == selectedID }),
              !group.isDefault else {
            return items
        }
        let ids = Set(group.itemIDs)
        return items.filter { ids.contains($0.id) }
    }

    var displayedItems: [ClipboardItem] {
        var base = filteredItems
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            base = base.filter { item in
                (item.textContent ?? "").lowercased().contains(query)
                || (item.customTitle ?? "").lowercased().contains(query)
                || (item.sourceApp?.name ?? "").lowercased().contains(query)
            }
        }
        // Pinned cards float to the top, keeping their relative order.
        return base.filter { $0.isPinned } + base.filter { !$0.isPinned }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned = !items[idx].isPinned
        saveData()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text, .url, .code, .color:
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let path = item.imagePath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                pb.setData(data, forType: .tiff)
            }
        }
        ClipboardStore.copySound?.play()

        if AppSettings.shared.moveToFrontOnCopy {
            moveItemToFront(item)
        }
    }

    private func moveItemToFront(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx != 0 else { return }
        let moved = items.remove(at: idx)
        items.insert(moved, at: 0)
        saveData()
    }

    func addItem(_ item: ClipboardItem) {
        UserDefaults.standard.set(totalCopied + 1, forKey: totalCopiedKey)

        // Deduplicate text-based content: if the same value is already stored,
        // refresh and bump it to the top instead of adding a duplicate.
        if let text = item.textContent,
           let existingIdx = items.firstIndex(where: { $0.type == item.type && $0.textContent == text }) {
            var existing = items.remove(at: existingIdx)
            existing.timestamp = Date()
            items.insert(existing, at: 0)
            saveData()
            return
        }

        items.insert(item, at: 0)
        if items.count > 500 {
            let removed = items.removeLast()
            deleteFiles(of: removed)
        }
        saveData()
    }

    func setTitle(_ title: String?, for item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].customTitle = title
        saveData()
    }

    func updateText(_ text: String, for item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].textContent = text
        saveData()
    }

    func persist() {
        saveData()
    }

    func clearAll() {
        for item in items {
            deleteFiles(of: item)
        }
        items.removeAll()
        for i in groups.indices {
            groups[i].itemIDs.removeAll()
        }
        saveData()
    }

    func clearGroup(_ group: ClipboardGroup) {
        if group.isDefault {
            clearAll()
            return
        }
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        let ids = Set(groups[idx].itemIDs)
        for item in items where ids.contains(item.id) {
            deleteFiles(of: item)
        }
        items.removeAll { ids.contains($0.id) }
        for i in groups.indices {
            groups[i].itemIDs.removeAll { ids.contains($0) }
        }
        saveData()
    }

    func removeItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        for i in groups.indices {
            groups[i].itemIDs.removeAll { $0 == item.id }
        }
        deleteFiles(of: item)
        saveData()
    }

    private func deleteFiles(of item: ClipboardItem) {
        if let path = item.imagePath {
            persistence.deleteImage(atPath: path)
        }
        if let preview = item.previewImagePath {
            persistence.deleteImage(atPath: preview)
        }
    }

    func renameGroup(_ group: ClipboardGroup, to name: String, colorIndex: Int?, emoji: String?) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[idx].name = name
        groups[idx].colorIndex = colorIndex
        groups[idx].emoji = emoji
        saveData()
    }

    func createGroup(name: String, retention: RetentionPeriod = .never,
                     colorIndex: Int? = nil, emoji: String? = nil) {
        let group = ClipboardGroup(name: name, retention: retention,
                                   colorIndex: colorIndex, emoji: emoji)
        groups.append(group)
        saveData()
    }

    func setRetention(_ period: RetentionPeriod, for groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].retention = period
        saveData()
        applyRetentionPolicies()
    }

    func deleteGroup(_ group: ClipboardGroup) {
        guard !group.isDefault else { return }
        groups.removeAll { $0.id == group.id }
        saveData()
    }

    func addItem(_ item: ClipboardItem, toGroup groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[idx].itemIDs.contains(item.id) {
            groups[idx].itemIDs.append(item.id)
        }
        saveData()
    }

    func removeItem(_ item: ClipboardItem, fromGroup groupID: UUID) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[idx].itemIDs.removeAll { $0 == item.id }
        saveData()
    }

    func applyRetentionPolicies() {
        let now = Date()
        let itemsByID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false

        // Apply per-group retention (drops the item from the group, not history).
        for i in groups.indices {
            let group = groups[i]
            guard !group.isDefault, let interval = group.retention.timeInterval else { continue }
            let cutoff = now.addingTimeInterval(-interval)
            let before = groups[i].itemIDs.count
            groups[i].itemIDs.removeAll { itemID in
                guard let item = itemsByID[itemID] else { return false }
                return item.timestamp < cutoff && !item.isPinned
            }
            if groups[i].itemIDs.count != before { changed = true }
        }

        // Apply the default ("Все") group retention to items that aren't
        // pinned into any subgroup. If it's set to "Никогда" — keep forever.
        let subgroupItemIDs = Set(groups.filter { !$0.isDefault }.flatMap { $0.itemIDs })
        if let interval = groups.first(where: { $0.isDefault })?.retention.timeInterval {
            let cutoff = now.addingTimeInterval(-interval)
            let toRemove = items.filter { item in
                item.timestamp < cutoff && !item.isPinned && !subgroupItemIDs.contains(item.id)
            }
            if !toRemove.isEmpty {
                let removeIDs = Set(toRemove.map { $0.id })
                items.removeAll { removeIDs.contains($0.id) }
                for i in groups.indices {
                    groups[i].itemIDs.removeAll { removeIDs.contains($0) }
                }
                for item in toRemove { deleteFiles(of: item) }
                changed = true
            }
        }

        if changed { saveData() }
    }

    /// Debounced persistence: snapshots state on the main thread after a short
    /// quiet period, then encodes and writes on a background queue.
    private func saveData() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let snapshot = StoreData(items: self.items, groups: self.groups)
            self.saveQueue.async { self.persistence.save(snapshot) }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Force any pending write to complete now (call on quit).
    func flushPendingSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = StoreData(items: items, groups: groups)
        saveQueue.sync { _ = self.persistence.save(snapshot) }
    }
}
