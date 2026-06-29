import SwiftUI
import AppKit

// MARK: - Menu item model

struct CardMenuItem {
    var title: String
    var systemImage: String
    var keyEquivalent: String = ""
    var modifiers: NSEvent.ModifierFlags = []
    var isSeparator: Bool = false
    var isDestructive: Bool = false
    var submenu: [CardMenuItem]? = nil
    var action: () -> Void = {}

    static func separator() -> CardMenuItem {
        CardMenuItem(title: "", systemImage: "", isSeparator: true)
    }
}

private final class ActionBox {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

// MARK: - Right-click styled menu

struct CardContextMenu: NSViewRepresentable {
    // Built lazily on right-click so it always reflects current store state
    // (e.g. newly created groups) without forcing the card to re-render.
    let items: () -> [CardMenuItem]

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    func makeNSView(context: Context) -> NSView {
        let view = MenuHostView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.items = items
        (nsView as? MenuHostView)?.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        var items: () -> [CardMenuItem]
        init(items: @escaping () -> [CardMenuItem]) { self.items = items }

        @objc func fire(_ sender: NSMenuItem) {
            (sender.representedObject as? ActionBox)?.action()
        }

        func buildMenu() -> NSMenu {
            let menu = build(from: items())
            menu.appearance = NSAppearance(named: .vibrantLight)
            return menu
        }

        private func build(from items: [CardMenuItem]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for item in items {
                if item.isSeparator {
                    menu.addItem(.separator())
                    continue
                }
                let menuItem = NSMenuItem(title: item.title,
                                          action: #selector(fire(_:)),
                                          keyEquivalent: item.keyEquivalent)
                menuItem.target = self
                menuItem.keyEquivalentModifierMask = item.modifiers
                menuItem.representedObject = ActionBox(item.action)
                menuItem.isEnabled = true

                if let image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil) {
                    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                    menuItem.image = image.withSymbolConfiguration(config)
                }

                if item.isDestructive {
                    menuItem.attributedTitle = NSAttributedString(
                        string: item.title,
                        attributes: [.foregroundColor: NSColor.systemRed]
                    )
                }

                if let submenu = item.submenu {
                    menuItem.submenu = build(from: submenu)
                    menuItem.action = nil
                }

                menu.addItem(menuItem)
            }
            return menu
        }
    }

    final class MenuHostView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only intercept right-clicks (or Ctrl+left) so left clicks / drags
            // pass through to the SwiftUI card below.
            if let event = NSApp.currentEvent {
                switch event.type {
                case .rightMouseDown, .rightMouseUp:
                    return super.hitTest(point)
                case .leftMouseDown where event.modifierFlags.contains(.control):
                    return super.hitTest(point)
                default:
                    return nil
                }
            }
            return nil
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            coordinator?.buildMenu()
        }
    }
}
