import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    static let showAsWindow = Notification.Name("AIMon.showAsWindow")
    static let hideToStatusBar = Notification.Name("AIMon.hideToStatusBar")
    static let quitApp = Notification.Name("AIMon.quitApp")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    // Alarm / flashing state
    private var flashTimer: Timer?
    private var flashOn = false
    private var isAlarming = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observe()
        startRefreshLoop()
        ClaudeService.shared.fetchPlan() // auto-detect subscription plan once at launch

        // Launch behavior: when started by the login agent (--at-login), stay
        // quietly in the menu bar. A manual launch shows the window as usual.
        if CommandLine.arguments.contains("--at-login") {
            NSApp.setActivationPolicy(.accessory)
        } else {
            showWindow()
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleShowAsWindow), name: .showAsWindow, object: nil)
        nc.addObserver(self, selector: #selector(handleHideToStatusBar), name: .hideToStatusBar, object: nil)
        nc.addObserver(self, selector: #selector(handleQuit), name: .quitApp, object: nil)
    }

    // Closing the window must NOT quit the app — it folds into the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Re-launching from Finder / Dock while folded brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    // MARK: - Status item (menu bar)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusButton()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            if let window = window, window.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                togglePopover()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "창으로 보기", action: #selector(handleShowAsWindow), keyEquivalent: "")
        let refreshItem = NSMenuItem(title: "새로고침", action: #selector(refreshNow), keyEquivalent: "r")
        let quitItem = NSMenuItem(title: "AI.Mon 종료", action: #selector(handleQuit), keyEquivalent: "q")
        [openItem, refreshItem, quitItem].forEach { $0.target = self }
        menu.addItem(openItem)
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        if let button = statusItem.button {
            let point = NSPoint(x: 0, y: button.bounds.height + 4)
            menu.popUp(positioning: nil, at: point, in: button)
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover.contentSize = NSSize(width: 380, height: 250)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainView(isWindowMode: false))
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Standalone window

    private func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(isWindowMode: true))
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.title = "AI.Mon"
            w.setContentSize(NSSize(width: 380, height: 250))
            w.minSize = NSSize(width: 340, height: 200)
            w.delegate = self
            w.isReleasedWhenClosed = false
            w.identifier = NSUserInterfaceItemIdentifier("AIMonMainWindow")
            w.center()
            window = w
        }
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyOpacity()
    }

    private func hideWindowToStatusBar() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // Intercept the red close button: fold into the menu bar instead of closing.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindowToStatusBar()
        return false
    }

    private func applyOpacity() {
        window?.alphaValue = CGFloat(ConfigManager.shared.config.windowOpacity)
    }

    // MARK: - Notification handlers

    @objc private func handleShowAsWindow() { showWindow() }
    @objc private func handleHideToStatusBar() { hideWindowToStatusBar() }
    @objc private func handleQuit() { NSApp.terminate(nil) }

    @objc private func refreshNow() {
        ClaudeService.shared.fetchUsage(sessionKey: ConfigManager.shared.config.claudeSessionKey)
    }

    // MARK: - Refresh loop

    private func startRefreshLoop() {
        refreshNow()
        let t = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    // MARK: - Observing usage for the menu bar label + alarm

    private func observe() {
        let service = ClaudeService.shared
        Publishers.CombineLatest(service.$utilization5h, service.$utilization7d)
            .receive(on: RunLoop.main)
            .sink { [weak self] u5, u7 in
                self?.handleUsage(u5: u5, u7: u7)
            }
            .store(in: &cancellables)

        ConfigManager.shared.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
                self?.applyOpacity()
                self?.handleUsage(u5: ClaudeService.shared.utilization5h,
                                  u7: ClaudeService.shared.utilization7d)
            }
            .store(in: &cancellables)
    }

    private func handleUsage(u5: Double, u7: Double) {
        updateStatusButton()

        // Alarm if EITHER the 5-hour or weekly usage crosses the threshold.
        let cfg = ConfigManager.shared.config
        let shouldAlarm = cfg.alarmEnabled
            && !cfg.claudeSessionKey.isEmpty
            && (u5 >= cfg.alarmThreshold || u7 >= cfg.alarmThreshold)

        if shouldAlarm && !isAlarming {
            startFlashing()
        } else if !shouldAlarm && isAlarming {
            stopFlashing()
        }
    }

    // MARK: - Flashing

    private func startFlashing() {
        isAlarming = true
        flashTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self, let button = self.statusItem.button else { return }
            self.flashOn.toggle()
            button.alphaValue = self.flashOn ? 1.0 : 0.25
        }
        RunLoop.main.add(t, forMode: .common)
        flashTimer = t
        updateStatusButton()
    }

    private func stopFlashing() {
        isAlarming = false
        flashTimer?.invalidate()
        flashTimer = nil
        flashOn = false
        statusItem.button?.alphaValue = 1.0
        updateStatusButton()
    }

    // MARK: - Status button rendering

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let cfg = ConfigManager.shared.config
        let service = ClaudeService.shared

        // Icon. Menu bar status buttons ignore contentTintColor for template
        // images (the system forces the menu bar color), so the alarm icon is
        // a baked red, non-template image instead.
        button.contentTintColor = nil
        if isAlarming {
            button.image = Self.warningImage()
        } else {
            let icon = Self.appIconImage()
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
        }

        // Percentage label (only once connected)
        if cfg.claudeSessionKey.isEmpty {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.imagePosition = .imageLeading
            let pct5h = Int((service.utilization5h * 100).rounded())
            let pct7d = Int((service.utilization7d * 100).rounded())
            let color: NSColor = isAlarming ? .systemRed : .labelColor
            button.attributedTitle = NSAttributedString(
                string: " \(pct5h)% | \(pct7d)%",
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.menuBarFont(ofSize: 0)
                ]
            )
        }
    }

    // MARK: - Images

    static func appIconImage() -> NSImage {
        if let path = Bundle.main.path(forResource: "app_icon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.isTemplate = false
            return img
        }
        let fallback = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "AI.Mon")
        return fallback ?? NSImage()
    }

    static func warningImage() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        guard let base = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                 accessibilityDescription: "사용량 경고")?
            .withSymbolConfiguration(cfg) else { return NSImage() }

        // Bake a red copy so the menu bar renders it red (non-template).
        let size = base.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        base.draw(in: rect)
        NSColor.systemRed.set()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}
