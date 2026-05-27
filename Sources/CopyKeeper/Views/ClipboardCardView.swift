import SwiftUI
import AppKit

struct ClipboardCardView: View {
    let item: ClipboardItem
    var isFocused: Bool = false
    var shortcutIndex: Int? = nil
    @EnvironmentObject var store: ClipboardStore
    @State private var isCopied = false
    @State private var isHovered = false
    @State private var loadedImage: NSImage?

    private var highlighted: Bool { isHovered || isFocused }

    private let cardWidth: CGFloat = 206
    private let cardHeight: CGFloat = 236
    private let radius: CGFloat = 18

    private var highlight: Color { store.activeColor }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerBand
                bodyView
            }
            .frame(width: cardWidth, height: cardHeight)
            .liquidGlassPlate(
                RoundedRectangle(cornerRadius: radius, style: .continuous),
                rimStrength: highlighted ? 1.3 : 0.9,
                stroke: highlighted ? highlight : nil,
                strokeWidth: 1.5,
                shadowRadius: highlighted ? 20 : 13,
                shadowY: highlighted ? 9 : 6,
                shadowOpacity: highlighted ? 0.42 : 0.30
            )
            .overlay(alignment: .bottomTrailing) {
                if let n = shortcutIndex {
                    Text("⌘\(n)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                        .padding(7)
                }
            }

            if isCopied {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    Label(Loc.s("Скопировано", "Copied"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .transition(.opacity)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear { loadImageIfNeeded() }
        .onChange(of: item.previewImagePath) { _ in loadImageIfNeeded() }
        .onChange(of: item.imagePath) { _ in loadImageIfNeeded() }
        .onDrag {
            NSItemProvider(object: item.id.uuidString as NSString)
        } preview: {
            dragPreview
        }
        .onTapGesture(count: 2) {
            copyToPasteboard()
            dismissPanel()
            simulatePaste()
        }
        .onTapGesture(count: 1) {
            store.focusedItemID = item.id
            performCopy()
        }
        .overlay(CardContextMenu(items: menuItems))
    }

    // MARK: - Context menu

    private var menuItems: [CardMenuItem] {
        var items: [CardMenuItem] = [
            CardMenuItem(title: Loc.s("Вставить", "Paste"), systemImage: "arrow.down.doc",
                         keyEquivalent: "\r") { performPaste() },
            CardMenuItem(title: Loc.s("Скопировать", "Copy"), systemImage: "doc.on.doc",
                         keyEquivalent: "c", modifiers: .command) { performCopy() },
            .separator(),
            CardMenuItem(title: Loc.s("Переименовать", "Rename"), systemImage: "pencil",
                         keyEquivalent: "r", modifiers: .command) { renameItem() }
        ]

        if isEditable {
            items.append(CardMenuItem(title: Loc.s("Редактировать", "Edit"), systemImage: "square.and.pencil",
                                      keyEquivalent: "e", modifiers: .command) { editItem() })
        }

        let subgroups = store.groups.filter { !$0.isDefault }
        if !subgroups.isEmpty {
            items.append(CardMenuItem(
                title: Loc.s("Добавить в группу", "Add to Group"),
                systemImage: "folder",
                submenu: subgroups.map { group in
                    CardMenuItem(title: group.name, systemImage: "folder") {
                        store.addItem(item, toGroup: group.id)
                    }
                }
            ))
        }

        items.append(.separator())
        items.append(CardMenuItem(title: Loc.s("Удалить", "Delete"), systemImage: "trash",
                                   keyEquivalent: "\u{8}", isDestructive: true) {
            deleteItem()
        })
        return items
    }

    private func deleteItem() {
        if AppSettings.shared.deleteWithoutConfirmation
            || Confirm.destructive(Loc.s("Удалить карточку?", "Delete card?"),
                                   info: Loc.s("Это действие нельзя отменить.", "This action cannot be undone.")) {
            store.removeItem(item)
        }
    }

    private func performPaste() {
        copyToPasteboard()
        dismissPanel()
        simulatePaste()
    }

    private func performCopy() {
        copyToPasteboard()
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            dismissPanel()
            isCopied = false
        }
    }

    private var isEditable: Bool {
        item.type == .text || item.type == .code
    }

    private func renameItem() {
        store.renamingItemID = item.id
    }

    private func editItem() {
        store.editingItemID = item.id
    }

    // MARK: - Header band

    private var headerBand: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(timeAgo(item.timestamp))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            iconView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(colors: [headerColor, headerColor.opacity(0.78)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // glassy sheen across the top of the accent band
                LinearGradient(colors: [Color.white.opacity(0.14), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .blendMode(.plusLighter)
            }
        )
    }

    @ViewBuilder
    private var iconView: some View {
        if let iconData = item.sourceApp?.iconData,
           let nsImage = NSImage(data: iconData) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        } else {
            Image(systemName: typeIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var bodyView: some View {
        if item.type == .url {
            urlBody
        } else if item.type == .image {
            imageBody
        } else if item.type == .color {
            colorBody
        } else {
            standardBody
        }
    }

    // Color layout: fill the whole body with the color, value centered.
    private var colorBody: some View {
        let nsColor = parseColorString(item.textContent ?? "") ?? .gray
        return ZStack {
            Color(nsColor)
            Text(item.textContent ?? "")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(nsColor.isLightColor ? .black.opacity(0.8) : .white)
                .padding(.horizontal, 8)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Image layout: full-bleed image filling the whole card body.
    private var imageBody: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(imageContent)
            .clipped()
    }

    private func loadImageIfNeeded() {
        guard loadedImage == nil else { return }
        let path = item.type == .image ? item.imagePath : (item.type == .url ? item.previewImagePath : nil)
        if let path { loadedImage = NSImage(contentsOfFile: path) }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let nsImage = loadedImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.04)
                Image(systemName: "photo")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Link layout: full-bleed Open Graph image filling the card,
    // title + URL pinned to the bottom.
    private var urlBody: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(urlImage)
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let faviconData = item.sourceApp?.faviconData,
                       let nsImg = NSImage(data: faviconData) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .frame(width: 15, height: 15)
                    }
                    Text(urlTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(item.textContent ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var urlImage: some View {
        if let nsImage = loadedImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(0.04)
                Image(systemName: "link")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if item.type != .image && item.type != .url {
            HStack {
                Text(charCountText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
            }
        }
    }

    // MARK: - Drag preview

    private var dragPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(headerColor)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        .fixedSize()
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case .text:
            Text(item.textContent ?? "")
                .font(.system(size: 11))
                .lineLimit(9)
                .foregroundColor(.white.opacity(0.85))

        case .code:
            Text(item.textContent ?? "")
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(10)
                .foregroundColor(.white.opacity(0.85))

        case .url:
            EmptyView() // handled by urlBody

        case .image:
            EmptyView() // handled by imageBody

        case .color:
            EmptyView() // handled by colorBody
        }
    }

    // MARK: - Derived values

    private var title: String {
        switch item.type {
        case .url:
            if let text = item.textContent, let url = URL(string: text) {
                return url.host ?? Loc.s("Ссылка", "Link")
            }
            return Loc.s("Ссылка", "Link")
        case .image:
            return Loc.s("Изображение", "Image")
        case .color:
            return Loc.s("Цвет", "Color")
        case .code, .text:
            if let name = item.sourceApp?.name, !name.isEmpty {
                return name
            }
            return item.type == .code ? Loc.s("Код", "Code") : Loc.s("Текст", "Text")
        }
    }

    private var urlTitle: String {
        if let text = item.textContent, let url = URL(string: text) {
            return url.host ?? text
        }
        return item.textContent ?? Loc.s("Ссылка", "Link")
    }

    private var displayTitle: String {
        if let custom = item.customTitle, !custom.isEmpty { return custom }
        return typeLabel
    }

    private var typeLabel: String {
        switch item.type {
        case .text:  return Loc.s("Текст", "Text")
        case .url:   return Loc.s("Ссылка", "Link")
        case .code:  return Loc.s("Код", "Code")
        case .image: return Loc.s("Изображение", "Image")
        case .color: return Loc.s("Цвет", "Color")
        }
    }

    private var charCountText: String {
        switch item.type {
        case .image:
            return Loc.s("изображение", "image")
        default:
            let n = item.textContent?.count ?? 0
            return "\(n) \(Loc.s("симв.", "chars"))"
        }
    }

    private var typeIcon: String {
        switch item.type {
        case .text:  return "doc.text"
        case .url:   return "link"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .color: return "paintpalette"
        }
    }

    private var headerColor: Color {
        switch item.type {
        case .text:  return Color(red: 0.82, green: 0.48, blue: 0.12)
        case .url:   return Color(red: 0.18, green: 0.42, blue: 0.88)
        case .code:  return Color(red: 0.44, green: 0.35, blue: 0.82)
        case .image: return Color(red: 0.85, green: 0.26, blue: 0.32)
        case .color: return Color(red: 0.86, green: 0.30, blue: 0.56)
        }
    }

    // MARK: - Actions

    private func copyToPasteboard() {
        store.copyToClipboard(item)
    }

    private func dismissPanel() {
        NotificationCenter.default.post(name: .cpTogglePanel, object: nil)
    }

    private func simulatePaste() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let vKey: CGKeyCode = 9 // V key
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

}
