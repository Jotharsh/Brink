import AppKit
import EdgelitCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let pipeline = AudioPipeline()
    private lazy var engine = GlowEngine(pipeline: pipeline)
    private lazy var tap = AudioTap(pipeline: pipeline)
    private let watcher = NotificationWatcher()
    private var statusItem: NSStatusItem!
    private var lastAudioError: String?

    // MARK: lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "rays", accessibilityDescription: "Edgelit")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        tap.onActivity = { [weak self] in self?.engine.audioChanged() }
        tap.onError = { [weak self] message in self?.lastAudioError = message }
        watcher.onBanner = { [weak self] texts in self?.banner(texts) }
        watcher.onCallEnded = { [weak self] in self?.engine.clearCalls() }

        Log.write("launch: screen recording \(AudioTap.hasPermission ? "allowed" : "not allowed"), accessibility \(NotificationWatcher.isTrusted ? "allowed" : "not allowed")")
        applyListeners()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop(); watcher.stop()
    }

    /// Starts or stops the listeners to match the settings and what macOS has allowed.
    private func applyListeners() {
        if settings.music && AudioTap.hasPermission { tap.start() } else if !settings.music { tap.stop() }
        if (settings.notifications || settings.calls) && NotificationWatcher.isTrusted { watcher.start() } else { watcher.stop() }
    }

    private func banner(_ texts: [String]) {
        let c = NotificationClassifier.classify(texts)
        switch c.kind {
        case .call:
            guard settings.calls else { return }
            engine.pulse(kind: .call, color: settings.callColor)
            watcher.watchCall(true)
        case .notification:
            engine.pulse(kind: .notification, color: notificationColor(for: c))
        }
    }

    private func notificationColor(for c: Classified) -> RGB { settings.matchAppColour ? c.color : settings.notificationColor }

    // MARK: edgelit:// links

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s), url.scheme == "edgelit" else { return }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ k: String) -> String? { q.first { $0.name == k }?.value }
        switch url.host {
        case "notify":
            let c = NotificationClassifier.classify([value("app") ?? "", value("text") ?? ""])
            engine.pulse(kind: .notification, color: notificationColor(for: c))
        case "call": engine.pulse(kind: .call, color: settings.callColor)
        case "clear": engine.clearCalls()
        case "music-demo": engine.runMusicDemo()
        default: break
        }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Edgelit", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(toggle("Music animation", on: settings.music, #selector(toggleMusic)))
        menu.addItem(toggle("Notification glow", on: settings.notifications, #selector(toggleNotifications)))
        menu.addItem(toggle("Call glow", on: settings.calls, #selector(toggleCalls)))
        menu.addItem(.separator())

        menu.addItem(action("Customise…", #selector(showSettings), key: ","))
        menu.addItem(toggle("Show on all displays", on: settings.allDisplays, #selector(toggleDisplays)))
        menu.addItem(.separator())

        // Permissions, in plain words.
        menu.addItem(permissionItem(ok: AudioTap.hasPermission, name: "Screen Recording (for music)",
                                    action: #selector(grantScreen)))
        menu.addItem(permissionItem(ok: NotificationWatcher.isTrusted, name: "Accessibility (for notifications)",
                                    action: #selector(grantAccessibility)))
        if !AudioTap.hasPermission || !NotificationWatcher.isTrusted {
            menu.addItem(action("Restart Edgelit (after allowing, to apply)", #selector(restart)))
        }
        if let e = lastAudioError, settings.music, AudioTap.hasPermission {
            let item = NSMenuItem(title: "Audio problem: \(e)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let test = NSMenuItem(title: "Try it", action: nil, keyEquivalent: "")
        let testMenu = NSMenu()
        testMenu.addItem(action("Notification", #selector(testNotification)))
        testMenu.addItem(action("Incoming call", #selector(testCall)))
        testMenu.addItem(action("Stop call", #selector(stopCall)))
        testMenu.addItem(action("Music demo (10 s)", #selector(testMusic)))
        test.submenu = testMenu
        menu.addItem(test)
        menu.addItem(.separator())
        menu.addItem(action("Show log in Finder", #selector(showLog)))
        menu.addItem(action("Quit Edgelit", #selector(quit), key: "q"))
    }

    private func toggle(_ title: String, on: Bool, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self; i.state = on ? .on : .off
        return i
    }

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    private func permissionItem(ok: Bool, name: String, action sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: ok ? "\(name): allowed" : "Allow \(name)…", action: ok ? nil : sel, keyEquivalent: "")
        i.target = self; i.isEnabled = !ok
        return i
    }

    // MARK: actions

    @objc private func toggleMusic() { settings.music.toggle(); applyListeners() }
    @objc private func toggleNotifications() { settings.notifications.toggle(); applyListeners() }
    @objc private func toggleCalls() { settings.calls.toggle(); applyListeners() }
    @objc private func toggleDisplays() { settings.allDisplays.toggle(); engine.rebuildWindows() }
    private var settingsWindow: NSWindow?

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(tryMusic: { [weak self] in self?.engine.runMusicDemo() },
                                    tryNotification: { [weak self] in self?.testNotification() },
                                    tryCall: { [weak self] in self?.testCall() },
                                    stopCall: { [weak self] in self?.engine.clearCalls() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Edgelit"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func grantScreen() {
        if !CGRequestScreenCaptureAccess() {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
        // macOS only applies this after the app restarts; try again a bit later in case it was already on.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.applyListeners() }
    }

    @objc private func grantAccessibility() {
        NotificationWatcher.promptForAccess()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        // Check again every few seconds for a minute, so the glow starts working as soon as it is allowed.
        for s in stride(from: 3.0, through: 60.0, by: 3.0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + s) { [weak self] in self?.applyListeners() }
        }
    }

    @objc private func testNotification() { engine.pulse(kind: .notification, color: notificationColor(for: NotificationClassifier.classify(["Messages"]))) }
    @objc private func testCall() { engine.pulse(kind: .call, color: settings.callColor) }
    @objc private func stopCall() { engine.clearCalls() }
    @objc private func testMusic() { engine.runMusicDemo() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// macOS only applies a new Screen Recording or Accessibility permission to a fresh launch.
    @objc private func restart() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    @objc private func showLog() { NSWorkspace.shared.activateFileViewerSelecting([Log.url]) }

    private func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
}
