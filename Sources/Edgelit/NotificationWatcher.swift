import AppKit
import ApplicationServices
import EdgelitCore

/// Notices when macOS shows a notification banner, by watching the Notification Center process through the
/// Accessibility API. Apple offers no official way to be told about other apps' notifications, so this is
/// best-effort: it needs the Accessibility permission and may need adjusting on new macOS versions.
final class NotificationWatcher {
    static let bundleID = "com.apple.notificationcenterui"

    var onBanner: (([String]) -> Void)?
    var onCallEnded: (() -> Void)?

    private var observer: AXObserver?
    private var attachedPID: pid_t = 0
    private var poll: Timer?
    private var lastFired: CFTimeInterval = 0
    private var callWatch = false
    private var callMisses = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccess() {
        let opts = ["AXTrustedCheckOptTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        stop()
        attach()
        // Notification Center can restart; re-attach if its process changed. Also drives call-end detection.
        poll = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.pollTick() }
    }

    func stop() {
        poll?.invalidate(); poll = nil
        detach()
    }

    /// Call while a call glow is showing, so it ends when the call banner goes away.
    func watchCall(_ on: Bool) { callWatch = on; callMisses = 0 }

    // MARK: attach

    private func attach() {
        guard Self.isTrusted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else { return }
        let pid = app.processIdentifier
        guard pid != attachedPID else { return }
        detach()

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<NotificationWatcher>.fromOpaque(refcon).takeUnretainedValue().bannerAppeared()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let element = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(obs, element, name as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs
        attachedPID = pid
    }

    private func detach() {
        if let obs = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        observer = nil
        attachedPID = 0
    }

    private func pollTick() {
        if attachedPID == 0 || NSRunningApplication(processIdentifier: attachedPID) == nil { detach(); attach() }
        if callWatch {
            // The call glow stays until no banner on screen looks like a call any more (two checks in a row).
            if NotificationClassifier.isLiveCall(Self.bannerTexts(pid: attachedPID)) { callMisses = 0 } else { callMisses += 1 }
            if callMisses >= 3 { callWatch = false; onCallEnded?() }
        }
    }

    // MARK: banner

    fileprivate func bannerAppeared() {
        let now = CACurrentMediaTime()
        guard now - lastFired > 0.8 else { return }        // one banner often fires several events
        // Give the banner a moment to fill in its text.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let texts = Self.bannerTexts(pid: self.attachedPID)
            guard !texts.isEmpty else { return }
            self.lastFired = CACurrentMediaTime()
            self.onBanner?(texts)
        }
    }

    /// All the readable text in Notification Center's windows right now.
    static func bannerTexts(pid: pid_t) -> [String] {
        guard pid != 0 else { return [] }
        let app = AXUIElementCreateApplication(pid)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement] else { return [] }
        var out: [String] = []
        for w in list { collect(w, depth: 0, into: &out) }
        return out
    }

    private static func collect(_ el: AXUIElement, depth: Int, into out: inout [String]) {
        guard depth < 8, out.count < 24 else { return }
        for attr in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty, !out.contains(t) { out.append(t) }
            }
        }
        var kids: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success, let list = kids as? [AXUIElement] {
            for k in list { collect(k, depth: depth + 1, into: &out) }
        }
    }
}
