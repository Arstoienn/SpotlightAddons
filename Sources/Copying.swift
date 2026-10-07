import AppKit
import SwiftUI

// Copying the answer: by the button at the end of the card, or by Return while the pointer is on
// the card or its panel. What is copied is the answer as a number another program can read, 2.5
// and not 5/2 or x = 5/2.
@Observable final class Copying {
    static let shared = Copying()

    var available = false   // there is something to copy for what is typed
    var done = false        // it has just been copied, and the card says so for a moment
    var symbol = "function" // the card's sign: f(x) for an answer, a folder or a page for a path
    var isPlace = false     // what is typed is a path: the button and Return go there instead
    @ObservationIgnored var go: () -> Void = {}
    @ObservationIgnored var text: () -> String? = { nil }
    @ObservationIgnored var copied: () -> Void = {}
    @ObservationIgnored private var generation = 0

    @discardableResult func copy() -> Bool {
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
                Image(systemName: copying.isPlace ? "folder" : copying.done ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                if copying.done { Text("Copied").font(.system(size: 12, weight: .medium)) }
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .overlay(ClickTarget { copying.copy() })
            .help(copying.isPlace ? "Show in Finder" : "Copy the answer")
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

// Return, while it is ours to take. Spotlight has the keyboard, and Return there opens the first
// thing in its list; with the pointer resting on the card, Return copies the answer instead and
// goes no further. Every other key, and Return at any other time, passes untouched and unread.
// The tap is only switched on while the card is up.
final class ReturnKey {
    var take: () -> Bool = { false }   // true if Return was used, and is not to reach Spotlight
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
            let key = Unmanaged<ReturnKey>.fromOpaque(refcon!).takeUnretainedValue()
            // The system switches a tap off if it is slow, or on some input; put it back.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if key.isOn, let tap = key.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let held = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            guard type == .keyDown, code == 36 || code == 76, held.isEmpty, key.take() else { return Unmanaged.passUnretained(event) }
            return nil
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return Log.note("Return could not be watched: no event tap") }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        Log.note("watching for Return while the card is up")
    }
}

extension Location {
    // A file is shown selected in its folder; a folder is opened.
    func show() {
        if isFolder { NSWorkspace.shared.open(url) } else { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
