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

    /// Set right before the app writes to the pasteboard itself, so the
    /// monitor skips capturing our own copy as a new (duplicate) item.
    var ignoreNextChange = false

    var persistence = PersistenceManager()

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
        let base = filteredItems
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter { item in
            (item.textContent ?? "").lowercased().contains(query)
            || (item.customTitle ?? "").lowercased().contains(query)
            || (item.sourceApp?.name ?? "").lowercased().contains(query)
        }
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
        NSSound(named: "Frog")?.play()

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

        // Apply per-group retention
        for i in groups.indices {
            let group = groups[i]
            guard !group.isDefault, let interval = group.retention.timeInterval else { continue }
            let cutoff = now.addingTimeInterval(-interval)
            let idsToRemove: [UUID] = group.itemIDs.compactMap { itemID in
                guard let item = items.first(where: { $0.id == itemID }) else { return nil }
                return item.timestamp < cutoff ? itemID : nil
            }
            groups[i].itemIDs.removeAll { idsToRemove.contains($0) }
        }

        // Apply the default ("Все") group retention to items that aren't
        // pinned into any subgroup. If it's set to "Никогда" — keep forever.
        let subgroupItemIDs = Set(groups.filter { !$0.isDefault }.flatMap { $0.itemIDs })
        let defaultInterval = groups.first(where: { $0.isDefault })?.retention.timeInterval

        let toRemove: [ClipboardItem]
        if let interval = defaultInterval {
            let cutoff = now.addingTimeInterval(-interval)
            toRemove = items.filter { item in
                item.timestamp < cutoff && !subgroupItemIDs.contains(item.id)
            }
        } else {
            toRemove = []
        }
        for item in toRemove {
            removeItem(item)
        }

        saveData()
    }

    private func saveData() {
        let data = StoreData(items: items, groups: groups)
        persistence.save(data)
    }
}
