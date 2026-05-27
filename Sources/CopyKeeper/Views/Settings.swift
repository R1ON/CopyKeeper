import SwiftUI
import AppKit
import Carbon
import ServiceManagement

// MARK: - Localization

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, ru, en
    var id: String { rawValue }
}

enum Loc {
    static func s(_ ru: String, _ en: String) -> String {
        AppSettings.shared.resolvedLanguage == .ru ? ru : en
    }

    static func items(_ n: Int) -> String {
        if AppSettings.shared.resolvedLanguage == .ru {
            let mod10 = n % 10, mod100 = n % 100
            let word: String
            if mod10 == 1 && mod100 != 11 {
                word = "элемент"
            } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
                word = "элемента"
            } else {
                word = "элементов"
            }
            return "\(n) \(word)"
        }
        return "\(n) \(n == 1 ? "item" : "items")"
    }
}

// MARK: - Confirmation helper

enum Confirm {
    @discardableResult
    static func destructive(_ message: String,
                            info: String = "",
                            confirmTitle: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        if !info.isEmpty { alert.informativeText = info }
        let confirm = alert.addButton(withTitle: confirmTitle ?? Loc.s("Удалить", "Delete"))
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: Loc.s("Отмена", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - App settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let deleteWithoutConfirmation = "com.copykeeper.deleteWithoutConfirmation"
        static let language = "com.copykeeper.language"
        static let moveToFrontOnCopy = "com.copykeeper.moveToFrontOnCopy"
    }

    @Published var deleteWithoutConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(deleteWithoutConfirmation, forKey: Keys.deleteWithoutConfirmation)
        }
    }

    @Published var moveToFrontOnCopy: Bool {
        didSet {
            UserDefaults.standard.set(moveToFrontOnCopy, forKey: Keys.moveToFrontOnCopy)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("CopyKeeper: launch-at-login update failed: \(error.localizedDescription)")
        }
    }

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }

    var resolvedLanguage: AppLanguage {
        switch language {
        case .auto:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return code == "ru" ? .ru : .en
        default:
            return language
        }
    }

    private init() {
        deleteWithoutConfirmation = UserDefaults.standard.bool(forKey: Keys.deleteWithoutConfirmation)
        moveToFrontOnCopy = UserDefaults.standard.object(forKey: Keys.moveToFrontOnCopy) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let raw = UserDefaults.standard.string(forKey: Keys.language) ?? AppLanguage.auto.rawValue
        language = AppLanguage(rawValue: raw) ?? .auto
    }
}

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    let onClose: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var tab = 0

    var body: some View {
        ZStack {
            glassBackground

            VStack(spacing: 0) {
                header

                Picker("", selection: $tab) {
                    Text(Loc.s("Основные", "General")).tag(0)
                    Text(Loc.s("Время жизни", "Lifetime")).tag(1)
                    Text(Loc.s("Горячие клавиши", "Hotkeys")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

                Group {
                    switch tab {
                    case 0: GeneralSettingsTab()
                    case 1: RetentionSettingsTab(store: store)
                    default: HotkeySettingsTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 440, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Text(Loc.s("Настройки", "Settings"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain).hoverHighlight()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var glassBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.40)
            RadialGradient(
                colors: [Color(red: 1.0, green: 0.55, blue: 0.2).opacity(0.16), .clear],
                center: .init(x: 0.15, y: 1.0),
                startRadius: 0, endRadius: 380
            )
        }
    }
}

// MARK: - General tab

struct GeneralSettingsTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            toggleRow(isOn: $settings.deleteWithoutConfirmation,
                      title: Loc.s("Удалять отдельные карточки без подтверждения",
                                   "Delete individual cards without confirmation"),
                      subtitle: Loc.s("Групповые действия всегда требуют подтверждения.",
                                      "Group actions always require confirmation."))

            toggleRow(isOn: $settings.moveToFrontOnCopy,
                      title: Loc.s("Перемещать карточку в начало при копировании",
                                   "Move card to the top when copied"),
                      subtitle: Loc.s("Скопированная запись становится первой в списке.",
                                      "The copied item becomes the first in the list."))

            toggleRow(isOn: $settings.launchAtLogin,
                      title: Loc.s("Запускать при входе в систему",
                                   "Launch at login"),
                      subtitle: Loc.s("Приложение будет открываться автоматически после входа.",
                                      "The app starts automatically after you log in."))

            VStack(alignment: .leading, spacing: 8) {
                Text(Loc.s("Язык", "Language"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Picker("", selection: $settings.language) {
                    Text(Loc.s("Системный", "System")).tag(AppLanguage.auto)
                    Text("Русский").tag(AppLanguage.ru)
                    Text("English").tag(AppLanguage.en)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

        }
        .padding(22)
        }
    }

    private func toggleRow(isOn: Binding<Bool>, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.orange)
        }
    }
}

// MARK: - Retention (lifetime) tab

struct RetentionSettingsTab: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.s("Сколько хранить записи в каждой группе. Старые удаляются автоматически.",
                       "How long to keep items in each group. Older ones are removed automatically."))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                        retentionRow(group, index: index)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private func retentionRow(_ group: ClipboardGroup, index: Int) -> some View {
        let color = GroupBarView.color(for: group, fallbackIndex: index)
        HStack(spacing: 10) {
            if let emoji = group.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 15))
                    .frame(width: 20)
            } else if group.isDefault {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 20)
            } else {
                Circle().fill(color).frame(width: 9, height: 9)
                    .frame(width: 20)
            }

            Text(group.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Picker("", selection: retentionBinding(for: group)) {
                ForEach(RetentionPeriod.allCases) { period in
                    Text(period.localizedName).tag(period)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .tint(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private func retentionBinding(for group: ClipboardGroup) -> Binding<RetentionPeriod> {
        Binding(
            get: { store.groups.first(where: { $0.id == group.id })?.retention ?? .oneWeek },
            set: { store.setRetention($0, for: group.id) }
        )
    }
}

// MARK: - Hotkey tab

struct HotkeySettingsTab: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var settings = HotkeySettings.load()
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            Text(Loc.s("Сочетание клавиш для открытия панели",
                       "Shortcut to open the panel"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)

            Button(action: toggleRecording) {
                Text(recording ? Loc.s("Нажмите сочетание…", "Press shortcut…") : settings.displayString)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(recording ? Color.orange.opacity(0.25) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(recording ? Color.orange : Color.clear, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain).hoverHighlight()

            Text(Loc.s("Нажмите поле и задайте сочетание с модификатором (⌘ ⌥ ⌃ ⇧). Сохраняется автоматически.",
                       "Click the field and set a shortcut with a modifier (⌘ ⌥ ⌃ ⇧). Saved automatically."))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(22)
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if recording { stopRecording(); return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.isEmpty else { return nil }

            var s = settings
            s.keyCode = event.keyCode
            s.command = flags.contains(.command)
            s.shift = flags.contains(.shift)
            s.option = flags.contains(.option)
            s.control = flags.contains(.control)
            let label = (event.charactersIgnoringModifiers ?? "").uppercased()
            s.keyLabel = label.isEmpty ? "Key\(event.keyCode)" : label

            settings = s
            s.save()
            NotificationCenter.default.post(name: .cpReloadHotkey, object: nil)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
