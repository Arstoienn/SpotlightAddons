import AppKit
import ApplicationServices

// Follows what is typed into Spotlight's search field, through the Accessibility API.
//
// Spotlight posts a value-changed notification for every element it updates, hundreds per
// keystroke as its results redraw, so the search field is remembered when it takes focus and
// everything else is ignored by identity, without asking Spotlight anything.
final class SpotlightWatcher {
    var onChange: (String) -> Void = { _ in }

    private var observer: AXObserver?
    private var app: AXUIElement?
    private var field: AXUIElement?
    private var lastLook = Date.distantPast

    func start() {
        // Spotlight is restarted now and then (and by `killall Spotlight`); follow the new one.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if launched?.bundleIdentifier == "com.apple.Spotlight" { self?.attach() }
        }
        attach()
    }

    private func attach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        field = nil
        guard let spotlight = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first
        else { return }

        let pid = spotlight.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            Unmanaged<SpotlightWatcher>.fromOpaque(refcon!).takeUnretainedValue().handle(element, notification as String)
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXValueChangedNotification, kAXFocusedUIElementChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        self.app = app
        observer = created
        if let focused = element(app, kAXFocusedUIElementAttribute) { take(focused) }
        Log.note("attached to Spotlight\(field == nil ? ", no search field yet" : "")")
    }

    private func handle(_ element: AXUIElement, _ notification: String) {
        if notification == kAXFocusedUIElementChangedNotification {
            take(element)
        } else if let field, CFEqual(element, field) {
            onChange(string(field, kAXValueAttribute) ?? "")
        } else if Date().timeIntervalSince(lastLook) > 0.25 {
            // Something else changed. Now and then, no oftener, see that the field followed is
            // still the one being typed into: Spotlight can make a new one without a word.
            lastLook = Date()
            if let app, let focused = self.element(app, kAXFocusedUIElementAttribute), field.map({ !CFEqual($0, focused) }) ?? true,
               string(focused, kAXRoleAttribute) == kAXTextFieldRole {
                Log.note("the search field was replaced")
                take(focused)
            }
        }
    }

    // What is in the search field at this moment.
    func current() -> String? { field.flatMap { string($0, kAXValueAttribute) } }

    private func element(_ e: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(e, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    // Opening, Spotlight moves focus to its search field and then straight on to its window, so
    // only a text field taking focus replaces the one followed; anything else leaves it be. A
    // closed Spotlight is noticed by its window fading out, not by focus.
    private func take(_ element: AXUIElement) {
        guard string(element, kAXRoleAttribute) == kAXTextFieldRole else { return }
        field = element
        onChange(string(element, kAXValueAttribute) ?? "")
    }

    // Spotlight's panel as drawn and its search field, in points from the top left of the main
    // display. Spotlight's window is sometimes the panel itself and sometimes, the same window
    // resized, the panel with a 40-point margin round it for the shadow; it switches between the
    // two while open. The field sits 59 points in from the panel's edge, so a window whose edge is
    // much further out than that has the margin, and that gives the panel's width, which does not
    // change. Every later frame is measured against that width.
    func geometry() -> (window: CGRect, field: CGRect, placement: Placement)? {
        guard let field else { return nil }
        let fieldFrame = frame(field)
        let containing = Self.windows().filter { $0.bounds.contains(fieldFrame) }
        guard let window = containing.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
        else { return nil }
        let width = window.bounds.width - (fieldFrame.minX - window.bounds.minX > 80 ? 80 : 0)
        return (Self.panelRect(window.bounds, width), fieldFrame, Placement(window: window.id, width: width))
    }

    // Which of Spotlight's windows holds the panel, and the panel's width.
    struct Placement {
        var window: CGWindowID
        var width: CGFloat
    }

    // The panel within a window of whichever size it is at the moment.
    static func panelRect(_ bounds: CGRect, _ width: CGFloat) -> CGRect {
        let extra = bounds.width - width
        if abs(extra - 80) < 1 { return bounds.insetBy(dx: 40, dy: 40) }   // the shadow margin, all round
        return CGRect(x: bounds.minX + max(0, extra) / 2, y: bounds.minY, width: width, height: bounds.height)
    }

    // Where the panel is now and how opaque, asked of its one window only: cheap enough to ask
    // every frame, so the card can follow Spotlight while it is dragged. Nil once it is gone.
    static func panel(_ p: Placement) -> (rect: CGRect, alpha: Double)? {
        guard let w = (CGWindowListCopyWindowInfo([.optionIncludingWindow], p.window) as? [[String: Any]])?.first,
              w[kCGWindowIsOnscreen as String] as? Bool == true,
              let b = w[kCGWindowBounds as String] as! CFDictionary?, let bounds = CGRect(dictionaryRepresentation: b)
        else { return nil }
        return (panelRect(bounds, p.width), w[kCGWindowAlpha as String] as? Double ?? 0)
    }

    // How opaque Spotlight's panel is, or nil when it has none on screen. Closing, it fades out in
    // about 0.1 s, then leaves the invisible window up for another 0.7 s.
    static func alpha() -> Double? {
        windows().filter { $0.layer == 23 }.map(\.alpha).max()
    }

    static func windows() -> [(id: CGWindowID, bounds: CGRect, alpha: Double, layer: Int)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard w[kCGWindowOwnerName as String] as? String == "Spotlight",
                  let id = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let b = w[kCGWindowBounds as String] as! CFDictionary?, let bounds = CGRect(dictionaryRepresentation: b)
            else { return nil }
            return (id, bounds, w[kCGWindowAlpha as String] as? Double ?? 0, w[kCGWindowLayer as String] as? Int ?? 0)
        }
    }
}

private func value(_ e: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, attribute as CFString, &v) == .success ? v : nil
}

private func string(_ e: AXUIElement, _ attribute: String) -> String? { value(e, attribute) as? String }


private func frame(_ e: AXUIElement) -> CGRect {
    var origin = CGPoint.zero, size = CGSize.zero
    if let v = value(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &origin) }
    if let v = value(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &size) }
    return CGRect(origin: origin, size: size)
}

// What the card did and why, for finding out when it goes missing: ~/Library/Logs/SpotlightPlus.log.
// Never what was typed, only how long it was.
enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SpotlightPlus.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func note(_ message: String) {
        guard Prefs.log else { return }
        let line = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
        // Started afresh once it has grown, so that it never amounts to much.
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 200_000,
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
