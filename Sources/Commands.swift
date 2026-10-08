import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

// The app's own entries in Spotlight's list. Core Spotlight lets an app put its things there;
// these are not documents but things to do. One chosen comes back to the app as an activity.
// (Spotlight Add-ons itself is in the list too, as any app is: choosing that only starts it.)
enum Entry: String, CaseIterable {
    case clipboardHistory = "clipboard-history"
    case settings = "settings"

    private var title: String { self == .settings ? "Spotlight Add-ons Preferences" : "Clipboard History" }
    private var summary: String { self == .settings ? "Change how Spotlight Add-ons answers" : "Open Spotlight's clipboard history" }
    private var symbol: String { self == .settings ? "gearshape" : "clipboard" }
    private var words: [String] {
        self == .settings ? ["preferences", "settings", "spotlight plus", "plus"] : ["clipboard", "history", "pasteboard", "clip"]
    }

    // Said again at every launch, and when one is chosen: it costs nothing, puts right an index
    // that has lost them, and keeps them recent.
    static func index() {
        let items = allCases.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = entry.title
            attributes.contentDescription = entry.summary
            attributes.keywords = entry.words
            attributes.thumbnailData = icon(entry.symbol)
            // Where it comes in the list is Spotlight's to decide. These are what it is given to
            // go on: that this is the user's own, kept on purpose, and in use as of now.
            attributes.rankingHint = 100
            attributes.userCurated = true
            attributes.userCreated = true
            attributes.userOwned = true
            attributes.lastUsedDate = Date()
            attributes.contentModificationDate = Date()
            let item = CSSearchableItem(uniqueIdentifier: entry.rawValue, domainIdentifier: "actions", attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            Log.note(error.map { "the entries could not be put in Spotlight's list: \($0.localizedDescription)" }
                          ?? "Clipboard History and Spotlight Add-ons Preferences are in Spotlight's list")
        }
    }

    // Takes them all out again, says so, and ends.
    static func forget() -> Never {
        let done = DispatchSemaphore(value: 0)
        CSSearchableIndex.default().deleteAllSearchableItems { error in
            print(error.map { "They could not be taken out: \($0.localizedDescription)" } ?? "Spotlight Add-ons' entries are out of Spotlight's list.")
            done.signal()
        }
        done.wait()
        exit(0)
    }

    // Which entry the activity is the choosing of, if it is one.
    static func chosen(_ activity: NSUserActivity) -> Entry? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return Entry(rawValue: identifier)
    }

    // What an entry is shown with: its sign, black on white as the app's own icon is, drawn here
    // rather than kept as a file.
    private static func icon(_ name: String) -> Data? {
        let pixels = 256, size = CGFloat(pixels)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                  .withSymbolConfiguration(.init(pointSize: size * 0.4, weight: .medium).applying(.init(paletteColors: [NSColor(white: 0.08, alpha: 1)])))
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let tile = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
        let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSGradient(starting: .white, ending: NSColor(white: 0.93, alpha: 1))?.draw(in: shape, angle: -90)
        NSColor(white: 0, alpha: 0.16).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        let fit = min(tile.width * 0.6 / symbol.size.width, tile.height * 0.6 / symbol.size.height)
        let drawn = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
        symbol.draw(in: NSRect(x: tile.midX - drawn.width / 2, y: tile.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

// Spotlight's clipboard history. Spotlight has no public way to be opened on a given view, so it
// is done with keys: ⌘Space and then ⌘4.
enum ClipboardHistory {
    // The Spotlight it was chosen in is still fading out, and ⌘Space before it has gone would
    // only close it. It is invisible after about 0.1 s, though its window stays up for another
    // 0.7 s, so it is the opacity that is waited for. Then ⌘Space, and as soon as Spotlight
    // starts to fade back in, ⌘4, sent to Spotlight's own process so that it can never land in
    // another app.
    static func open() {
        Log.note("asked for the clipboard history")
        DispatchQueue.global(qos: .userInteractive).async {
            wait(until: { (SpotlightWatcher.alpha() ?? 0) < 0.05 }, timeout: 1)
            press(49, to: nil)
            wait(until: { (SpotlightWatcher.alpha() ?? 0) > 0.1 }, timeout: 1)
            if let spotlight = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first {
                press(21, to: spotlight.processIdentifier)
            }
        }
    }

    private static func wait(until done: () -> Bool, timeout: TimeInterval) {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { usleep(5_000) }
    }

    // ⌘ and a key: to the system when there is no process to send it to, as ⌘Space, a system
    // shortcut, has to be.
    private static func press(_ key: CGKeyCode, to pid: pid_t?) {
        let source = CGEventSource(stateID: .hidSystemState)
        let command: CGKeyCode = 55
        for (code, down) in [(command, true), (key, true), (key, false), (command, false)] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = code == command && !down ? [] : .maskCommand
            if let pid { event?.postToPid(pid) } else { event?.post(tap: .cghidEventTap) }
        }
    }
}
