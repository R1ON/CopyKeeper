import SwiftUI
import AppKit

struct ClipboardPanelView: View {
    @EnvironmentObject var store: ClipboardStore
    @ObservedObject private var settings = AppSettings.shared
    @State private var searching = false

    private let corner: CGFloat = 26

    var body: some View {
        ZStack {
            background
                .contentShape(Rectangle())
                .onTapGesture { dismissTransients() }

            VStack(spacing: 0) {
                TopBarView(searchText: $store.searchText,
                           searching: $searching)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { dismissTransients() }

            if let id = store.editingItemID,
               let item = store.items.first(where: { $0.id == id }) {
                EditTextOverlay(item: item) {
                    store.editingItemID = nil
                }
                .environmentObject(store)
                .transition(.opacity)
            }

            if let mode = store.groupEditorMode {
                GroupEditorOverlay(mode: mode) {
                    store.groupEditorMode = nil
                }
                .environmentObject(store)
                .transition(.opacity)
            }

            if let id = store.renamingItemID,
               let item = store.items.first(where: { $0.id == id }) {
                RenameCardOverlay(item: item) {
                    store.renamingItemID = nil
                }
                .environmentObject(store)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedCorner(radius: corner, corners: [.topLeft, .topRight]))
        .overlay(
            RoundedCorner(radius: corner, corners: [.topLeft, .topRight])
                .stroke(glassRim(1.0), lineWidth: 1)
                .blendMode(.plusLighter)
        )
        // crisp bright lensing line along the very top edge
        .overlay(
            RoundedCorner(radius: corner, corners: [.topLeft, .topRight])
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .blur(radius: 0.5)
                .mask(
                    LinearGradient(colors: [.white, .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                        .frame(maxHeight: .infinity, alignment: .top)
                )
                .blendMode(.plusLighter)
        )
    }

    /// Tapping empty space clears card focus and collapses the search field.
    private func dismissTransients() {
        store.focusedItemID = nil
        if searching {
            store.searchText = ""
            withAnimation(.easeOut(duration: 0.15)) { searching = false }
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            // light neutral frost — kept translucent, just enough for legibility
            Color.black.opacity(0.18)

            // top-down sheen: bright at the rim, clear in the middle
            LinearGradient(
                colors: [Color.white.opacity(0.12), .clear, Color.black.opacity(0.06)],
                startPoint: .top, endPoint: .bottom
            )

            // faint cool ambient light pooling at the lower corners
            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .init(x: 0.15, y: 1.0),
                startRadius: 0, endRadius: 520
            )
            RadialGradient(
                colors: [Color(red: 0.6, green: 0.78, blue: 1.0).opacity(0.10), .clear],
                center: .init(x: 0.9, y: 1.0),
                startRadius: 0, endRadius: 480
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let items = store.displayedItems
        if items.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: store.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(.white.opacity(0.35))
                Text(store.searchText.isEmpty
                     ? Loc.s("Ничего не скопировано", "Nothing copied")
                     : Loc.s("Ничего не найдено", "Nothing found"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        } else {
            let pinnedCount = items.prefix { $0.isPinned }.count
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipboardCardView(item: item,
                                          isFocused: item.id == store.focusedItemID,
                                          shortcutIndex: index < 9 ? index + 1 : nil)

                        if index == pinnedCount - 1 && pinnedCount < items.count {
                            RoundedRectangle(cornerRadius: 0.5)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1, height: 116)
                                .padding(.horizontal, 6)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
                .padding(.top, 0)
            }
        }
    }
}

// MARK: - Top bar

struct TopBarView: View {
    @EnvironmentObject var store: ClipboardStore
    @Binding var searchText: String
    @Binding var searching: Bool
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            if searching {
                searchField
            } else {
                searchButton
                Divider()
                    .frame(height: 18)
                    .overlay(Color.white.opacity(0.12))
                GroupBarView()
            }

            Spacer(minLength: 0)

            ellipsisMenu
            closeButton
        }
        .frame(height: 52)
    }

    private var searchButton: some View {
        iconButton(system: "magnifyingglass") {
            withAnimation(.easeOut(duration: 0.15)) { searching = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            TextField(Loc.s("Поиск", "Search"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($searchFocused)
            Button {
                searchText = ""
                withAnimation(.easeOut(duration: 0.15)) { searching = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain).hoverHighlight()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassControl(Capsule())
        .frame(maxWidth: 280)
    }

    private var ellipsisMenu: some View {
        Menu {
            Button(Loc.s("Новая группа", "New Group")) { store.groupEditorMode = .create }
            Button(Loc.s("Статистика", "Statistics")) {
                NotificationCenter.default.post(name: .cpShowStatistics, object: nil)
            }
            Button(Loc.s("Настройки", "Settings")) {
                NotificationCenter.default.post(name: .cpShowSettings, object: nil)
            }
            Divider()
            Button(Loc.s("Очистить все", "Clear All"), role: .destructive) {
                if Confirm.destructive(Loc.s("Очистить весь буфер?", "Clear entire clipboard?"),
                                       info: Loc.s("Все скопированные элементы будут удалены.",
                                                   "All copied items will be deleted."),
                                       confirmTitle: Loc.s("Очистить", "Clear")) {
                    store.clearAll()
                }
            }
            Divider()
            Button(Loc.s("Выйти", "Quit")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .glassControl(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
    }

    private var closeButton: some View {
        iconButton(system: "xmark") {
            NotificationCenter.default.post(name: .cpTogglePanel, object: nil)
        }
    }

    private func iconButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .glassControl(Circle())
        }
        .buttonStyle(.plain).hoverHighlight()
    }
}

// MARK: - Edit text overlay

struct EditTextOverlay: View {
    @EnvironmentObject var store: ClipboardStore
    let item: ClipboardItem
    let onClose: () -> Void

    @State private var text: String
    @FocusState private var editorFocused: Bool

    init(item: ClipboardItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _text = State(initialValue: item.textContent ?? "")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Text(Loc.s("Редактировать", "Edit"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).hoverHighlight()
                }

                ZStack(alignment: .bottomTrailing) {
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .focused($editorFocused)
                        .padding(10)
                        .frame(height: 150)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))

                    HStack(spacing: 8) {
                        actionButton(Loc.s("Применить", "Apply"), color: Color.white.opacity(0.14)) {
                            apply(copy: false)
                        }
                        actionButton(Loc.s("Применить и скопировать", "Apply & Copy"),
                                     color: Color(red: 0.98, green: 0.55, blue: 0.2)) {
                            apply(copy: true)
                        }
                    }
                    .padding(10)
                }
            }
            .padding(16)
            .frame(width: 560)
            .liquidGlassSurface(cornerRadius: 18)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editorFocused = true }
        }
    }

    private func actionButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(color))
        }
        .buttonStyle(.plain).hoverHighlight()
    }

    private func apply(copy: Bool) {
        store.updateText(text, for: item)
        if copy {
            var updated = item
            updated.textContent = text
            store.copyToClipboard(updated)
            NotificationCenter.default.post(name: .cpTogglePanel, object: nil)
        }
        onClose()
    }
}

// MARK: - Group create / rename overlay

struct GroupEditorOverlay: View {
    @EnvironmentObject var store: ClipboardStore
    let mode: GroupEditorMode
    let onClose: () -> Void

    @State private var name = ""
    @State private var emoji = ""
    @State private var colorIndex = 0
    @State private var showEmojiGrid = false
    @FocusState private var focused: Bool

    // Full set of standard single-scalar emoji, generated from Unicode properties.
    static let allEmoji: [String] = {
        let ranges: [ClosedRange<UInt32>] = [
            0x1F600...0x1F64F, // emoticons
            0x1F300...0x1F5FF, // misc symbols & pictographs
            0x1F680...0x1F6FF, // transport & map
            0x1F900...0x1F9FF, // supplemental symbols & pictographs
            0x1FA70...0x1FAFF, // symbols & pictographs extended-A
            0x2600...0x26FF,   // misc symbols
            0x2700...0x27BF    // dingbats
        ]
        var result: [String] = []
        for range in ranges {
            for code in range {
                guard let scalar = Unicode.Scalar(code),
                      scalar.properties.isEmojiPresentation else { continue }
                result.append(String(scalar))
            }
        }
        return result
    }()

    private var isRename: Bool {
        if case .rename = mode { return true }
        return false
    }
    private var title: String {
        isRename ? Loc.s("Изменить группу", "Edit Group") : Loc.s("Новая группа", "New Group")
    }
    private var actionTitle: String {
        isRename ? Loc.s("Сохранить", "Save") : Loc.s("Создать", "Create")
    }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).hoverHighlight()
                }

                HStack(spacing: 8) {
                    emojiSlot

                    TextField(Loc.s("Название группы", "Group name"), text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .focused($focused)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        .onSubmit { save() }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8),
                          spacing: 10) {
                    ForEach(GroupBarView.palette.indices, id: \.self) { i in
                        Circle()
                            .fill(GroupBarView.palette[i])
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(Color.white, lineWidth: colorIndex == i ? 2.5 : 0)
                            )
                            .scaleEffect(colorIndex == i ? 1.12 : 1.0)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.1)) { colorIndex = i }
                            }
                    }
                }

                HStack {
                    Spacer()
                    Button(action: save) {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(GroupBarView.palette[colorIndex]))
                            .opacity(canSave ? 1 : 0.4)
                    }
                    .buttonStyle(.plain).hoverHighlight()
                    .disabled(!canSave)
                }
            }
            .padding(18)
            .frame(width: 380)
            .liquidGlassSurface(cornerRadius: 18)

            if showEmojiGrid {
                emojiPickerOverlay
                    .transition(.opacity)
            }
        }
        .onAppear { setup() }
    }

    private var emojiPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.12)) { showEmojiGrid = false }
                }

            VStack(spacing: 10) {
                HStack {
                    Text(Loc.s("Выберите эмодзи", "Choose emoji"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        emoji = ""
                        withAnimation(.easeOut(duration: 0.12)) { showEmojiGrid = false }
                    } label: {
                        Text(Loc.s("Без эмодзи", "No emoji"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain).hoverHighlight()
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { showEmojiGrid = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).hoverHighlight()
                }

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12),
                              spacing: 4) {
                        ForEach(GroupEditorOverlay.allEmoji, id: \.self) { choice in
                            Button {
                                emoji = choice
                                withAnimation(.easeOut(duration: 0.12)) { showEmojiGrid = false }
                            } label: {
                                Text(choice)
                                    .font(.system(size: 20))
                                    .frame(width: 32, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(emoji == choice ? Color.white.opacity(0.2) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain).hoverHighlight()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            .frame(width: 560, height: 300)
            .liquidGlassSurface(cornerRadius: 18)
        }
    }

    private var emojiSlot: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { showEmojiGrid.toggle() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(showEmojiGrid ? Color.white.opacity(0.4) : Color.white.opacity(0.12), lineWidth: 1)
                if emoji.isEmpty {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text(emoji).font(.system(size: 18))
                }
            }
            .frame(width: 40, height: 34)
        }
        .buttonStyle(.plain).hoverHighlight()
    }

    private func setup() {
        if case .rename(let id) = mode,
           let index = store.groups.firstIndex(where: { $0.id == id }) {
            name = store.groups[index].name
            emoji = store.groups[index].emoji ?? ""
            colorIndex = store.groups[index].colorIndex ?? (index % GroupBarView.palette.count)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespaces)
        let emojiValue = trimmedEmoji.isEmpty ? nil : trimmedEmoji
        switch mode {
        case .create:
            store.createGroup(name: trimmedName, colorIndex: colorIndex, emoji: emojiValue)
        case .rename(let id):
            if let group = store.groups.first(where: { $0.id == id }) {
                store.renameGroup(group, to: trimmedName, colorIndex: colorIndex, emoji: emojiValue)
            }
        }
        onClose()
    }
}

// MARK: - Card rename overlay

struct RenameCardOverlay: View {
    @EnvironmentObject var store: ClipboardStore
    let item: ClipboardItem
    let onClose: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(Loc.s("Переименовать", "Rename"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain).hoverHighlight()
                }

                TextField(Loc.s("Заголовок карточки", "Card title"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .onSubmit { save() }

                HStack {
                    Spacer()
                    Button(action: save) {
                        Text(Loc.s("Сохранить", "Save"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(store.activeColor))
                    }
                    .buttonStyle(.plain).hoverHighlight()
                }
            }
            .padding(18)
            .frame(width: 380)
            .liquidGlassSurface(cornerRadius: 18)
        }
        .onAppear {
            name = item.customTitle ?? defaultTitle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private var defaultTitle: String {
        switch item.type {
        case .text:  return Loc.s("Текст", "Text")
        case .url:   return Loc.s("Ссылка", "Link")
        case .code:  return Loc.s("Код", "Code")
        case .image: return Loc.s("Изображение", "Image")
        case .color: return Loc.s("Цвет", "Color")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        store.setTitle(trimmed.isEmpty ? nil : trimmed, for: item)
        onClose()
    }
}

