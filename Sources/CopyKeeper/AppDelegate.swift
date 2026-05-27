import AppKit
import SwiftUI
import Carbon

// MARK: - Notification Name Extension

extension Notification.Name {
    static let cpTogglePanel = Notification.Name("com.copykeeper.togglePanel")
    static let cpDebugShowPanel = Notification.Name("com.copykeeper.debugShowPanel")
    static let cpShowStatistics = Notification.Name("com.copykeeper.showStatistics")
    static let cpShowSettings = Notification.Name("com.copykeeper.showSettings")
    static let cpReloadHotkey = Notification.Name("com.copykeeper.reloadHotkey")
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var store = ClipboardStore()
    var statusItem: NSStatusItem?
    var panel: ClipboardPanel?
    var monitor: ClipboardMonitor?
    var hotKeyRef: EventHotKeyRef?
    var localHotKeyMonitor: Any?
    var retentionTimer: Timer?
    var currentHotkey = HotkeySettings.load()
    var settingsWindow: NSWindow?
    var statsWindow: NSWindow?
    var suppressHotkey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("CopyKeeper: application did finish launching")
        NSApp.setActivationPolicy(.accessory)
        panel = ClipboardPanel(store: store)
        setupStatusBar()
        setupHotkey()
        DistributedNotificationCenter.default().addObserver(self,
                                                            selector: #selector(showPanel),
                                                            name: .cpDebugShowPanel,
                                                            object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(openStatistics),
                                               name: .cpShowStatistics,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(openSettings),
                                               name: .cpShowSettings,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadHotkey),
                                               name: .cpReloadHotkey,
                                               object: nil)
        store.applyRetentionPolicies()
        monitor = ClipboardMonitor(store: store)
        monitor?.start()

        // Periodically enforce retention so short periods (1h, 10h) take effect at runtime.
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.applyRetentionPolicies()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = statusBarIcon()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func statusBarIcon() -> NSImage? {
        // Custom icon: drop trayIcon.png (monochrome template recommended) into Resources.
        if let url = Bundle.main.url(forResource: "trayIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true   // adapts to light/dark menu bar
            return image
        }
        let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyKeeper")
        symbol?.isTemplate = true
        return symbol
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: Loc.s("Показать/скрыть", "Show/Hide"),
                                  action: #selector(togglePanel),
                                  keyEquivalent: currentHotkey.keyLabel.count == 1
                                      ? currentHotkey.keyLabel.lowercased() : "")
        showItem.keyEquivalentModifierMask = currentHotkey.nsFlags
        menu.addItem(showItem)

        menu.addItem(NSMenuItem(title: Loc.s("Статистика", "Statistics"),
                                action: #selector(openStatistics),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: Loc.s("Настройки", "Settings"),
                                action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Loc.s("Очистить все", "Clear All"),
                                action: #selector(clearAll),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: Loc.s("Выйти", "Quit"),
                                action: #selector(quitApp),
                                keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let menu = buildStatusMenu()
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    func setupHotkey() {
        NotificationCenter.default.addObserver(self, selector: #selector(togglePanel),
                                               name: .cpTogglePanel, object: nil)

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hkID = EventHotKeyID()
                GetEventParameter(event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID)
                if hkID.id == 1 {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .cpTogglePanel, object: nil)
                    }
                }
                return noErr
            },
            1, &eventSpec, nil, nil
        )

        if installStatus != noErr {
            print("CopyKeeper: failed to install hotkey event handler, status: \(installStatus)")
        } else {
            print("CopyKeeper: hotkey event handler installed")
        }

        registerCarbonHotkey()

        localHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.suppressHotkey { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == self.currentHotkey.nsFlags, event.keyCode == self.currentHotkey.keyCode {
                NotificationCenter.default.post(name: .cpTogglePanel, object: nil)
                return nil
            }
            if event.keyCode == 53 { // Escape
                NotificationCenter.default.post(name: .cpTogglePanel, object: nil)
                return nil
            }
            return event
        }
    }

    private func registerCarbonHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        var hkID = EventHotKeyID()
        hkID.signature = 0x43505354 // 'CPST'
        hkID.id = 1
        let status = RegisterEventHotKey(UInt32(currentHotkey.keyCode),
                                         currentHotkey.carbonModifiers,
                                         hkID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            print("CopyKeeper: failed to register hotkey \(currentHotkey.displayString), status: \(status)")
        } else {
            print("CopyKeeper: registered hotkey \(currentHotkey.displayString)")
        }
    }

    @objc func reloadHotkey() {
        currentHotkey = HotkeySettings.load()
        registerCarbonHotkey()
    }

    @objc func openSettings() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        suppressHotkey = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let view = SettingsView(store: store, onClose: { [weak self] in
            self?.settingsWindow?.close()
        })
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func openStatistics() {
        if let window = statsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let view = StatisticsView(store: store, onClose: { [weak self] in
            self?.statsWindow?.close()
        })
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        window.center()
        statsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === settingsWindow {
            settingsWindow = nil
            suppressHotkey = false
        }
        if window === statsWindow {
            statsWindow = nil
        }
    }

    @objc func clearAll() {
        if Confirm.destructive(Loc.s("Очистить весь буфер?", "Clear entire clipboard?"),
                               info: Loc.s("Все скопированные элементы будут удалены.",
                                           "All copied items will be deleted."),
                               confirmTitle: Loc.s("Очистить", "Clear")) {
            store.clearAll()
        }
    }

    @objc func togglePanel() {
        panel?.toggle()
    }

    @objc func showPanel() {
        panel?.show()
    }

    @objc func quitApp() {
        cleanup()
        NSApp.terminate(nil)
    }

    private func cleanup() {
        monitor?.stop()
        retentionTimer?.invalidate()
        retentionTimer = nil
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let localHotKeyMonitor {
            NSEvent.removeMonitor(localHotKeyMonitor)
            self.localHotKeyMonitor = nil
        }
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
