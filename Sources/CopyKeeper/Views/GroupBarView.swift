import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GroupBarView: View {
    @EnvironmentObject var store: ClipboardStore
    @State private var dropTargetGroupID: UUID?
    @State private var hoveredGroupID: UUID?

    static let palette: [Color] = [
        Color(red: 1.0, green: 0.55, blue: 0.2),    // orange
        Color(red: 0.35, green: 0.7, blue: 1.0),    // blue
        Color(red: 0.7, green: 0.45, blue: 1.0),    // purple
        Color(red: 0.3, green: 0.82, blue: 0.6),    // green
        Color(red: 1.0, green: 0.45, blue: 0.7),    // pink
        Color(red: 0.3, green: 0.8, blue: 0.85),    // teal
        Color(red: 0.95, green: 0.35, blue: 0.35),  // red
        Color(red: 0.98, green: 0.8, blue: 0.25),   // yellow
        Color(red: 0.45, green: 0.5, blue: 0.92),   // indigo
        Color(red: 0.4, green: 0.9, blue: 0.75),    // mint
        Color(red: 0.62, green: 0.85, blue: 0.3),   // lime
        Color(red: 0.88, green: 0.35, blue: 0.78),  // magenta
        Color(red: 0.45, green: 0.8, blue: 0.95),   // sky
        Color(red: 1.0, green: 0.4, blue: 0.5),     // rose
        Color(red: 0.72, green: 0.52, blue: 0.38),  // brown
        Color(red: 0.55, green: 0.6, blue: 0.7)     // slate
    ]

    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }

    static func color(for group: ClipboardGroup, fallbackIndex: Int) -> Color {
        palette[(group.colorIndex ?? fallbackIndex) % palette.count]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                    groupPill(group, index: index)
                }

                Button(action: { store.groupEditorMode = .create }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .glassControl(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func groupPill(_ group: ClipboardGroup, index: Int) -> some View {
        let isSelected = isGroupSelected(group)
        let color = GroupBarView.color(for: group, fallbackIndex: index)
        let isDropTarget = dropTargetGroupID == group.id
        let isHovered = hoveredGroupID == group.id
        let fillColor: Color = isSelected
            ? color.opacity(0.9)
            : (isHovered ? color.opacity(0.22) : Color.white.opacity(0.001))

        let pill = pillLabel(group, color: color, isSelected: isSelected)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(isDropTarget ? color.opacity(0.5) : fillColor))
            .overlay(
                Capsule()
                    .strokeBorder(glassRim(isSelected ? 1.0 : 0.5), lineWidth: 1)
                    .blendMode(.plusLighter)
                    .opacity(isSelected || isHovered ? 1 : 0)
            )
            .overlay(Capsule().stroke(color, lineWidth: isDropTarget ? 2 : 0))
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .contentShape(Rectangle())

        pill
            .padding(.horizontal, 2)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .applyIf(!group.isDefault) { view in
                view.onDrop(of: [.text], isTargeted: dropBinding(for: group)) { providers in
                    handleDrop(providers, into: group)
                }
            }
            .onHover { hovering in
                if hovering {
                    hoveredGroupID = group.id
                } else if hoveredGroupID == group.id {
                    hoveredGroupID = nil
                }
            }
            .onTapGesture {
                store.selectedGroupID = group.isDefault ? nil : group.id
            }
            .contextMenu { pillContextMenu(group) }
    }

    @ViewBuilder
    private func pillLabel(_ group: ClipboardGroup, color: Color, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if let emoji = group.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 13))
            } else if group.isDefault {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            } else {
                Circle()
                    .fill(isSelected ? Color.white : color)
                    .frame(width: 7, height: 7)
            }
            Text(group.name)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private func dropBinding(for group: ClipboardGroup) -> Binding<Bool> {
        Binding(
            get: { dropTargetGroupID == group.id },
            set: { dropTargetGroupID = $0 ? group.id : nil }
        )
    }

    @ViewBuilder
    private func pillContextMenu(_ group: ClipboardGroup) -> some View {
        if !group.isDefault {
            Button(Loc.s("Изменить", "Edit")) { store.groupEditorMode = .rename(group.id) }
            Divider()
        }
        Button(Loc.s("Очистить группу", "Clear Group"), role: .destructive) {
            if Confirm.destructive(Loc.s("Очистить группу «\(group.name)»?", "Clear group “\(group.name)”?"),
                                   info: Loc.s("Записи группы будут удалены.", "Items in this group will be deleted."),
                                   confirmTitle: Loc.s("Очистить", "Clear")) {
                store.clearGroup(group)
            }
        }
        if !group.isDefault {
            Button(Loc.s("Удалить группу", "Delete Group"), role: .destructive) {
                if Confirm.destructive(Loc.s("Удалить группу «\(group.name)»?", "Delete group “\(group.name)”?"),
                                       info: Loc.s("Сама группа будет удалена. Записи останутся в истории.",
                                                   "The group will be removed. Items stay in history.")) {
                    store.deleteGroup(group)
                    if store.selectedGroupID == group.id {
                        store.selectedGroupID = nil
                    }
                }
            }
        }
        Menu("\(Loc.s("Хранение", "Retention")): \(group.retention.localizedName)") {
            ForEach(RetentionPeriod.allCases) { period in
                Button(period.localizedName) {
                    updateRetention(group: group, retention: period)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], into group: ClipboardGroup) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let uuid = UUID(uuidString: string) else { return }
            DispatchQueue.main.async {
                guard let item = store.items.first(where: { $0.id == uuid }) else { return }
                store.addItem(item, toGroup: group.id)
                NSSound(named: "Purr")?.play()
            }
        }
        return true
    }

    private func isGroupSelected(_ group: ClipboardGroup) -> Bool {
        if group.isDefault {
            return store.selectedGroupID == nil
        }
        return store.selectedGroupID == group.id
    }

    private func updateRetention(group: ClipboardGroup, retention: RetentionPeriod) {
        guard let idx = store.groups.firstIndex(where: { $0.id == group.id }) else { return }
        store.groups[idx].retention = retention
        let data = StoreData(items: store.items, groups: store.groups)
        store.persistence.save(data)
    }
}

extension View {
    @ViewBuilder
    func applyIf<V: View>(_ condition: Bool, transform: (Self) -> V) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
