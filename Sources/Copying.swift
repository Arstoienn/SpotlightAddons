import AppKit
import SwiftUI

// Copying the answer: by the button at the end of the card, or by Return while the pointer is on
// the card or its panel. What is copied is the answer as a number another program can read, 2.5
// and not 5/2 or x = 5/2.
@Observable final class Copying {
    static let shared = Copying()

    var available = false   // there is something to copy for what is typed
    var done = false        // it has just been copied, and the card says so for a moment
    var isPlace = false     // what is typed is a path: the button and Return go there instead
    var isCommand = false   // what is typed is a line for Terminal: the button and Return type it there instead
    @ObservationIgnored var go: () -> Void = {}
    @ObservationIgnored var text: () -> String? = { nil }
    @ObservationIgnored var copied: () -> Void = {}
    @ObservationIgnored private var generation = 0

    @discardableResult func copy() -> Bool {
        // A command is typed in Terminal, or, where it cannot be, nothing is done; either way Return goes no further.
        if isCommand { go(); return true }
        if isPlace { go(); return true }
        guard let text = text() else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied()
        done = true
        generation += 1
        let mine = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.generation == mine { self?.done = false }
        }
        return true
    }
}

// The button at the end of the card. The card and its panel are never the key window, where a
// SwiftUI button would not get its click, so the click is taken in AppKit.
struct CopyButton: View {
    private var copying = Copying.shared

    var body: some View {
        if copying.available {
            HStack(spacing: 5) {
                Image(systemName: copying.isCommand ? "keyboard" : copying.isPlace ? "folder" : copying.done ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                if copying.done { Text("Copied").font(.system(size: 12, weight: .medium)) }
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .overlay(ClickTarget { copying.copy() })
            .help(copying.isCommand ? "Type in Terminal, without running it" : copying.isPlace ? "Show in Finder" : "Copy the answer")
            .padding(.trailing, 12)
        }
    }
}

struct ClickTarget: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> ClickTargetView { ClickTargetView() }
    func updateNSView(_ view: ClickTargetView, context: Context) { view.action = action }
}

final class ClickTargetView: NSView {
    var action: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

// Keys, while they are ours to take. Spotlight has the keyboard: Return there opens the first thing
// in its list, the arrows move through it and Escape closes it. With the pointer resting on the
// card, Return copies the answer instead and goes no further; while a list of completions is open
// on the card, the arrows, Tab, Return and Escape work it. Every other key, and these at any other
// time, pass untouched and unread. The tap is only switched on while the card is up.
final class KeyTap {
    enum Key {
        case returnKey, tab, escape, up, down
        init?(code: Int64) {
            switch code {
            case 36, 76: self = .returnKey   // Return, and Enter on the keypad
            case 48: self = .tab
            case 53: self = .escape
            case 126: self = .up
            case 125: self = .down
            default: return nil
            }
        }
    }

    var take: (Key) -> Bool = { _ in false }   // true if the key was used, and is not to reach Spotlight
    private var tap: CFMachPort?

    var isOn = false {
        didSet {
            guard isOn != oldValue else { return }
            if isOn, tap == nil { create() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: isOn) }
        }
    }

    private func create() {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let keys = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            // The system switches a tap off if it is slow, or on some input; put it back.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if keys.isOn, let tap = keys.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let held = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            guard type == .keyDown, held.isEmpty, let key = Key(code: event.getIntegerValueField(.keyboardEventKeycode)), keys.take(key)
            else { return Unmanaged.passUnretained(event) }
            return nil
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return Log.note("keys could not be watched: no event tap") }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        Log.note("watching for Return, and the keys of a list, while the card is up")
    }
}

extension Location {
    // A file is shown selected in its folder; a folder is opened.
    func show() {
        if isFolder { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
