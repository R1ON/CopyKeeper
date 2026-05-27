import SwiftUI
import AppKit
import Carbon

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
    }

    @Published var deleteWithoutConfirmation: Bool {
        didSet {
            UserDefaults.standard.set(deleteWithoutConfirmation, forKey: Keys.deleteWithoutConfirmation)
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
        let raw = UserDefaults.standard.string(forKey: Keys.language) ?? AppLanguage.auto.rawValue
        language = AppLanguage(rawValue: raw) ?? .auto
    }
}

// MARK: - Settings window

struct SettingsView: View {
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
                    Text(Loc.s("Горячие клавиши", "Hotkeys")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

                Group {
                    if tab == 0 {
                        GeneralSettingsTab()
                    } else {
                        HotkeySettingsTab()
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
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $settings.deleteWithoutConfirmation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.s("Удалять отдельные карточки без подтверждения",
                               "Delete individual cards without confirmation"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Text(Loc.s("Групповые действия всегда требуют подтверждения.",
                               "Group actions always require confirmation."))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .toggleStyle(.switch)
            .tint(.orange)

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

            Spacer()
        }
        .padding(22)
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
