import SwiftUI
import AppKit
import Carbon

// MARK: - HotkeySettings

struct HotkeySettings: Codable, Equatable {
    var keyCode: UInt16
    var keyLabel: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    static let `default` = HotkeySettings(
        keyCode: UInt16(kVK_ANSI_C),
        keyLabel: "C",
        command: true, shift: true, option: false, control: false
    )

    private static let defaultsKey = "com.copykeeper.hotkey"

    static func load() -> HotkeySettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(HotkeySettings.self, from: data) else {
            return .default
        }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: HotkeySettings.defaultsKey)
        }
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if command { m |= UInt32(cmdKey) }
        if shift { m |= UInt32(shiftKey) }
        if option { m |= UInt32(optionKey) }
        if control { m |= UInt32(controlKey) }
        return m
    }

    var nsFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if command { f.insert(.command) }
        if shift { f.insert(.shift) }
        if option { f.insert(.option) }
        if control { f.insert(.control) }
        return f
    }

    var hasModifier: Bool { command || shift || option || control }

    var displayString: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        s += keyLabel.isEmpty ? "?" : keyLabel
        return s
    }
}
