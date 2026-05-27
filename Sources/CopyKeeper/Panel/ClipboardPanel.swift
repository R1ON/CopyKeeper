import AppKit
import SwiftUI
import Combine

final class ClipboardPanel: NSPanel {
    private var isAnimating = false
    private var resignObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var editingCancellable: AnyCancellable?
    private let store: ClipboardStore
    private let panelHeight: CGFloat = 344
    private let sideMargin: CGFloat = 0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(store: ClipboardStore) {
        self.store = store
        super.init(contentRect: NSRect(x: 0, y: 0, width: 900, height: panelHeight),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        // Bound to the Space it's shown on (no .canJoinAllSpaces/.stationary):
        // swiping to another desktop carries it away with the old Space, and it
        // never appears on the new one. The activeSpace observer then tidies up.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false

        let root = ClipboardPanelView().environmentObject(store)
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting

        // While the text editor overlay is open, fully disable the panel's
        // key handling so Delete/Enter etc. never reach the cards.
        let overlayActive = Publishers.CombineLatest3(
            store.$editingItemID, store.$groupEditorMode, store.$renamingItemID
        ).map { $0 != nil || $1 != nil || $2 != nil }

        editingCancellable = overlayActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self = self else { return }
                if active {
                    self.removeKeyMonitor()
                } else if self.isVisible {
                    self.installKeyMonitor()
                }
            }
    }

    private func restingFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = screen.width - sideMargin * 2
        return NSRect(x: screen.minX + sideMargin,
                      y: screen.minY,
                      width: width,
                      height: panelHeight)
    }

    func show() {
        guard !isAnimating else { return }
        let target = restingFrame()
        let start = NSRect(x: target.minX,
                           y: target.minY - panelHeight,
                           width: target.width,
                           height: target.height)

        setFrame(start, display: false)
        alphaValue = 0
        store.focusedItemID = nil
        store.hoveredItemID = nil
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        // Don't let macOS auto-focus the first control (the search button):
        // keep the container as first responder so nothing shows a focus ring
        // until the user explicitly interacts.
        makeFirstResponder(contentView)
        installKeyMonitor()

        isAnimating = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            self?.isAnimating = false
        }

        installDismissObserver()
    }

    func hide() {
        guard !isAnimating, isVisible else { return }
        // Dismiss any open editor overlays so the panel is clean on next open.
        store.editingItemID = nil
        store.renamingItemID = nil
        store.groupEditorMode = nil
        removeDismissObserver()
        removeKeyMonitor()
        let current = frame
        let target = NSRect(x: current.minX,
                            y: current.minY - panelHeight,
                            width: current.width,
                            height: current.height)

        isAnimating = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            animator().setFrame(target, display: true)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
            self?.isAnimating = false
        }
    }

    /// Hide instantly with no slide animation. Used on Space switches so the
    /// panel never flashes on the destination desktop (it lives on all Spaces).
    func hideImmediately() {
        guard isVisible else { return }
        store.editingItemID = nil
        store.renamingItemID = nil
        store.groupEditorMode = nil
        removeDismissObserver()
        removeKeyMonitor()
        isAnimating = false
        orderOut(nil)
        alphaValue = 1
    }

    func toggle() {
        if isVisible && !isAnimating {
            hide()
        } else if !isVisible {
            show()
        }
    }

    // MARK: - Dismiss when the app loses focus

    private func installDismissObserver() {
        removeDismissObserver()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
        // Dismiss when the user switches Spaces / desktops so the panel
        // doesn't linger over another workspace.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hideImmediately()
        }
    }

    private func removeDismissObserver() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
    }

    // MARK: - Keyboard navigation

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // ANSI key codes for the top-row digits 1…9.
    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    /// Copy an item, dismiss the panel, then synthesize ⌘V into the app behind.
    private func pasteItem(_ item: ClipboardItem) {
        store.copyToClipboard(item)
        hide()
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Don't hijack keys while editing text or managing a group.
        if store.editingItemID != nil || store.groupEditorMode != nil || store.renamingItemID != nil { return false }

        let items = store.displayedItems

        // ⌘1…⌘9 — paste the Nth visible card. Works even while the search
        // field is focused, so it's a true quick-paste shortcut.
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let digit = ClipboardPanel.digitKeyCodes[event.keyCode],
           digit <= items.count {
            pasteItem(items[digit - 1])
            return true
        }

        if firstResponder is NSText { return false }

        guard !items.isEmpty else { return false }

        let focusedIndex = items.firstIndex { $0.id == store.focusedItemID }
        let hasFocus = focusedIndex != nil
        let currentIndex = focusedIndex ?? 0

        switch event.keyCode {
        case 48: // Tab — focus first, or move to next (wrap)
            if !hasFocus {
                store.focusedItemID = items[0].id
            } else {
                store.focusedItemID = items[(currentIndex + 1) % items.count].id
            }
            return true

        case 123, 126: // Left / Up
            store.focusedItemID = hasFocus ? items[max(0, currentIndex - 1)].id : items[0].id
            return true

        case 124, 125: // Right / Down
            store.focusedItemID = hasFocus ? items[min(items.count - 1, currentIndex + 1)].id : items[0].id
            return true

        case 36, 76: // Return / Keypad Enter
            guard hasFocus else { return false }
            store.copyToClipboard(items[currentIndex])
            hide()
            return true

        case 51, 117: // Delete / Forward delete
            // Prefer the hovered card so the mouse can drive deletion; fall
            // back to the keyboard-focused one.
            let target = store.hoveredItemID.flatMap { id in items.first { $0.id == id } }
                ?? (hasFocus ? items[currentIndex] : nil)
            guard let item = target else { return false }
            if AppSettings.shared.deleteWithoutConfirmation
                || Confirm.destructive(Loc.s("Удалить карточку?", "Delete card?"),
                                       info: Loc.s("Это действие нельзя отменить.",
                                                   "This action cannot be undone.")) {
                let wasFocused = item.id == store.focusedItemID
                store.removeItem(item)
                if wasFocused {
                    let next = store.displayedItems
                    store.focusedItemID = currentIndex < next.count ? next[currentIndex].id : next.last?.id
                }
            }
            return true

        default:
            return false
        }
    }
}
