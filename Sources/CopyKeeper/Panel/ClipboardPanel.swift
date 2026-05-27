import AppKit
import SwiftUI
import Combine

final class ClipboardPanel: NSPanel {
    private var isAnimating = false
    private var resignObserver: NSObjectProtocol?
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
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
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
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
    }

    private func removeDismissObserver() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
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

    private func handleKey(_ event: NSEvent) -> Bool {
        // Don't hijack keys while editing text, managing a group, or typing in search.
        if store.editingItemID != nil || store.groupEditorMode != nil || store.renamingItemID != nil { return false }
        if firstResponder is NSText { return false }

        let items = store.displayedItems
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
            guard hasFocus else { return false }
            let item = items[currentIndex]
            if AppSettings.shared.deleteWithoutConfirmation
                || Confirm.destructive("Удалить карточку?",
                                       info: "Это действие нельзя отменить.") {
                store.removeItem(item)
                let next = store.displayedItems
                if currentIndex < next.count {
                    store.focusedItemID = next[currentIndex].id
                } else {
                    store.focusedItemID = next.last?.id
                }
            }
            return true

        default:
            return false
        }
    }
}
