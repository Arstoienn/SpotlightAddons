import AppKit
import ApplicationServices

// Spotlight Add-ons: type an equation into Spotlight, like "2n^2=10", and the answer appears on a
// card above it as you type, the way Spotlight's own calculator answers "2+2". It runs in the
// background with no window or Dock icon, and reads Spotlight's search field through
// Accessibility.

final class AppDelegate: NSObject, NSApplicationDelegate {
    let watcher = SpotlightWatcher()
    let panel = ResultPanel()
    let detail = DetailPanel()
    let keys = KeyTap()
    let settings = SettingsWindow()
    let welcome = Welcome()
    var text = ""
    var link: CADisplayLink?
    var placement: SpotlightWatcher.Placement?
    var spotlight = CGRect.zero   // where Spotlight's panel was at the last frame
    var moving = false
    var lastMove = Date.distantPast
    var lastAlpha = 1.0
    var typed = 0   // counts changes of text, so that a second look started for an old one gives up
    // Completions offered on the card while a call after @ is typed, and the text at which Escape
    // put them away, so that they stay away until something more is typed.
    var completion: Completion.List?
    var dismissed: String?
    var completionCaret: NSRange?
    var astronomyExpandRequested: String?
    // Kept out of App Nap. An app in the background with no window on screen has its timers and
    // animations slowed by macOS until they all but stop: the card was then put up but stayed
    // invisible, its fade-in never run, until the preferences were brought to the front. Nothing
    // runs while Spotlight is closed, so this costs nothing then, and the Mac still sleeps.
    var awake: NSObjectProtocol?

    // ans. The answer showing becomes ans when it is done with: copied, cleared, or Spotlight
    // closed on it. Until something else is typed, that same text still reads ans as it was
    // before, so that ans+1 does not climb each time it is looked at again.
    var shown: String?         // the text the card last answered
    var pointerAtCard = NSPoint(x: -1e6, y: -1e6)   // where the pointer was when the card last came up or changed
    var remembered: String?    // the text whose answer ans is
    var ansBefore: [Double] = []   // what ans was until then
    var ansNow: [Double] = (UserDefaults.standard.array(forKey: "answers") as? [Double])
        ?? (UserDefaults.standard.object(forKey: "ans") as? Double).map { [$0] } ?? []   // "ans" is where the one answer was kept before there could be several

    // Opened while already running, which is what choosing Spotlight Add-ons in Spotlight does:
    // the preferences come up, on the page that says how things stand, as an app with no Dock icon
    // would otherwise seem not to have opened at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show(status: true)
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Crash.watch()
        SettingsButton.open = { [weak self] in self?.settings.show() }
        // Opened by hand, it shows its preferences; opened by the login, it keeps quiet but for its note.
        let launch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: 0x70726474)   // 'prdt'
        let atLogin = launch?.enumCodeValue == 0x6C676974                                                   // 'lgit'
        if !atLogin, !Crash.reopened { DispatchQueue.main.async { [weak self] in self?.settings.show(status: true) } }
        Entry.removeAll()
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            welcome.show(.running)
            start()
        } else {
            welcome.show(.waitingForPermission)
            // Wait for the permission rather than asking to be opened again once it is given.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.welcome.show(.running)
                self?.start()
            }
        }
    }

    func start() {
        awake = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                      reason: "Answering what is typed into Spotlight")
        watcher.onChange = { [weak self] text in self?.update(text) }
        panel.onHover = { [weak self] in self?.expand() }
        Copying.shared.text = { [weak self] in self.flatMap { Solver.copy($0.text) } }
        Copying.shared.copied = { [weak self] in self?.remember() }
        Command.report = { Log.note($0) }
        // The button, or Return: a command is typed in Terminal, to be run there, and Spotlight's
        // field emptied; Terminal coming to the front then closes Spotlight. A path is shown.
        Copying.shared.go = { [weak self] in
            guard let self else { return }
            if let command = Command.parse(text) {
                if command.type() { watcher.clear() }
            } else {
                Location.parse(text)?.show()
            }
        }
        keys.take = { [weak self] key in self?.take(key) ?? false }
        NotificationCenter.default.addObserver(forName: Rates.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self, panel.isVisible, !detail.isOpen, Currency.conversion(text) != nil else { return }
            _ = present()
        }
        NotificationCenter.default.addObserver(forName: AstronomyEngine.changed, object: nil, queue: .main) { [weak self] notice in
            guard let self, notice.object as? String == text, !detail.isOpen, Astronomy.marked(text) else { return }
            guard present() else { astronomyExpandRequested = nil; return }
            if astronomyExpandRequested == text {
                astronomyExpandRequested = nil
                expand(byKey: true)
            }
        }
        watcher.start()
    }

    // A key while the card is up. With completions offered, the arrows choose among them, Tab and
    // Return write the chosen one into Spotlight's field, and Escape puts the list away; nothing
    // else is taken from Spotlight, and with no list these keys are Spotlight's but for Return.
    func take(_ key: KeyTap.Key) -> Bool {
        guard panel.isVisible else { return false }
        if var list = completion {
            switch key {
            case .up, .down:
                list.selected = min(max(list.selected + (key == .up ? -1 : 1), 0), list.items.count - 1)
                completion = list
                _ = present()
            case .tab, .returnKey:
                guard let edit = Completion.choose(list, in: Astronomy.catalogue) else { return true }
                // Written after the key is let go of, not inside the keyboard's event tap.
                DispatchQueue.main.async { [weak self] in self?.watcher.write(edit.text, selecting: edit.selection) }
            case .escape:
                dismissed = text
                completion = nil
                if Solver.solve(text) == nil || !present() { hide() }
            }
            return true
        }
        return key == .returnKey && returnTaken()
    }

    // Return copies only with the pointer resting on the card or its panel.
    func returnTaken() -> Bool {
        guard panel.isVisible else { return false }
        // A line after > is no search: Return types it in Terminal wherever the pointer is,
        // unless that is turned off. Nothing is run by it, only typed at the prompt.
        if let command = Command.parse(text), command.typeable, Options.commandReturn { return Copying.shared.copy() }
        // After @, Return opens the working, which a search of the web for the call would not
        // be; with the working open, it copies the answer as it does anywhere.
        if Astronomy.marked(text), !detail.isOpen {
            if Solver.details(text) != nil {
                DispatchQueue.main.async { [weak self] in self?.expand(byKey: true) }
            } else {
                astronomyExpandRequested = text
            }
            return true
        }
        guard Prefs.returnCopies, detail.isOpen || panel.frame.contains(NSEvent.mouseLocation) else { return false }
        // Otherwise a command is typed in Terminal only for a pointer moved onto the card, as
        // expand() asks, never one the card came up under. One that cannot be typed is taken
        // and does nothing, so that Spotlight does not open its first result instead.
        if let command = Command.parse(text), command.typeable {
            let pointer = NSEvent.mouseLocation
            guard hypot(pointer.x - pointerAtCard.x, pointer.y - pointerAtCard.y) > 2 else { return false }
        }
        return Copying.shared.copy()
    }

    func update(_ text: String) {
        // Typing on while the panel is open puts the panel away; the card follows what is typed.
        if detail.isOpen {
            guard text != self.text else { return }
            detail.close(animated: false)
        }
        // Spotlight says the field has changed several times for each key; once is enough.
        let caret = watcher.selection()
        if text == self.text, panel.isVisible, caret == completionCaret { return }
        completionCaret = caret
        if text.isEmpty { remember() }
        if text != self.text { astronomyExpandRequested = nil }
        self.text = text
        typed += 1
        Memory.answers = text == remembered ? ansBefore : ansNow
        // The clipboard is only read when it is asked for by name.
        if text.contains("clip") {
            let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            Memory.clip = copied.flatMap { Double($0.replacingOccurrences(of: "−", with: "-")) }
        }
        // After @, what fits where the caret is, unless Escape put the list away at this very text.
        let offered = Options.astronomy && text != dismissed ? Completion.list(text, caret: watcher.selection()?.location, in: Astronomy.catalogue) : nil
        if dismissed != nil, text != dismissed { dismissed = nil }
        // The choice kept while the same things are offered, as when only the caret moved.
        if var offered, let before = completion, before.items == offered.items { offered.selected = before.selected; completion = offered } else { completion = offered }
        guard completion != nil || Solver.solve(text) != nil else {
            let foreign = text.unicodeScalars.filter { $0.value > 0x7F }.count
            Log.note("typed \(text.count) characters\(foreign > 0 ? " (\(foreign) not ASCII)" : ""): nothing to show")
            return hide()
        }
        if present() { Log.note("typed \(text.count) characters: shown") } else { lost("no place for the card as it was typed") }
    }

    // The answer showing becomes ans.
    func remember() {
        guard let shown, shown != remembered else { return }
        Memory.answers = ansNow
        let values = Solver.values(shown)
        guard !values.isEmpty else { return }
        (ansBefore, ansNow, remembered) = (ansNow, values, shown)
        UserDefaults.standard.set(values, forKey: "answers")
        Memory.answers = text == remembered ? ansBefore : ansNow
    }

    // Puts the card up for the text as it stands, if Spotlight is there with room for it.
    func present() -> Bool {
        guard let card = completion.map(CardText.offering) ?? CardText.of(text), let geometry = watcher.geometry(),
              (SpotlightWatcher.alpha() ?? 0) > 0
        else { return false }
        placement = geometry.placement
        spotlight = geometry.window
        // Everything has an answer to copy but a number typed by itself. (Working out what the
        // answer is waits until it is asked for: this runs at every keystroke.)
        // A command has a button to type it in Terminal, but none where it cannot be typed.
        let command = Command.parse(text)
        let place = command == nil ? Location.parse(text) : nil
        Copying.shared.isCommand = command != nil
        Copying.shared.isPlace = place != nil
        Copying.shared.available = completion == nil && (!Astronomy.marked(text) || Solver.copy(text) != nil) && (command.map(\.typeable) ?? (Copying.shared.isPlace || NumberFacts.parse(Latex.plain(text)) == nil))
        shown = text
        pointerAtCard = NSEvent.mouseLocation
        panel.show(card, window: geometry.window)
        keys.isOn = true
        watch()
        return true
    }

    // The card has lost Spotlight: its window went, or began to fade. That is how Spotlight
    // closes, but it is also what it looks like for a moment when its results come and go and it
    // moves to another window. So the card goes, and is put back if a little later Spotlight is
    // still up with the same text in it.
    func lost(_ why: String) {
        Log.note("lost: \(why)")
        hide()
        let asked = typed
        for delay in [0.12, 0.3, 0.6, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, asked == typed, !panel.isVisible else { return }
                guard (SpotlightWatcher.alpha() ?? 0) > 0.5, watcher.current() == text else {
                    // Still gone at the last look: Spotlight has closed, on an answer that is now ans.
                    if delay == 1.0 { remember() }
                    return
                }
                if present() { Log.note("back after \(delay) s") }
            }
        }
    }

    // Every frame while the card is up, in step with the display.
    func watch() {
        guard link == nil, let screen = NSScreen.main else { return }
        lastAlpha = 1
        let link = screen.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    // Dragged, Spotlight's own position comes in fits and starts, and a card chasing it judders;
    // so the card fades out when the drag starts and back in where Spotlight is put down, once it
    // has been still for a moment. Closing, Spotlight fades out, and the card goes as soon as the
    // fade starts.
    @objc func frame(_ link: CADisplayLink) {
        guard let placement, let now = SpotlightWatcher.panel(placement) else { return retarget() }
        if now.alpha < 0.05 || (now.alpha < 0.95 && now.alpha < lastAlpha) { return lost("Spotlight's window at \(now.alpha)") }
        lastAlpha = now.alpha
        if now.rect.origin != spotlight.origin {
            spotlight = now.rect
            lastMove = Date()
            if !moving {
                moving = true
                detail.close(animated: false)
                panel.vanish()
            }
        } else if moving, Date().timeIntervalSince(lastMove) > 0.15 {
            moving = false
            panel.place(now.rect)
            panel.reappear()
        }
    }

    // The window followed has gone. If Spotlight is still up it has moved its panel to another
    // window, so find it again; otherwise Spotlight has closed.
    func retarget() {
        guard (SpotlightWatcher.alpha() ?? 0) > 0.5, let geometry = watcher.geometry() else { return lost("Spotlight's window gone") }
        Log.note("followed Spotlight to another window")
        placement = geometry.placement
        spotlight = geometry.window
        panel.place(geometry.window)
    }

    // The pointer on the card: the card grows into the working. The panel starts exactly where
    // the card is and covers it, so the card is put away underneath at once; it comes back, in
    // the same place, when the panel has shrunk back into it.
    // Return after @ opens it too, wherever the pointer is (byKey).
    func expand(byKey: Bool = false) {
        // Not while Spotlight is being dragged, or has only just been put down, nor over a list of completions.
        guard Date().timeIntervalSince(lastMove) > 0.3, completion == nil else { return }
        // Not for a pointer that has stayed where it was since the card came up or changed, as it
        // does at each key and when Spotlight opens again on what was typed before: the card came
        // to the pointer, not the pointer to the card.
        let pointer = NSEvent.mouseLocation
        guard byKey || hypot(pointer.x - pointerAtCard.x, pointer.y - pointerAtCard.y) > 2 else { return }
        guard !detail.isOpen, let answer = CardText.of(text), let details = Solver.details(text) else { return }
        // Spotlight as it is now: its list grows and shrinks with what is typed without moving it.
        let now = placement.flatMap { SpotlightWatcher.panel($0)?.rect } ?? spotlight
        let primary = NSScreen.screens.first?.frame.height ?? 0
        detail.show(answer, details, from: panel.frame, spotlightBottom: now == .zero ? nil : primary - now.maxY, level: panel.level,
                    onCovered: { [weak self] in self?.panel.conceal() },
                    onCollapsed: { [weak self] in
                        guard let self, (SpotlightWatcher.alpha() ?? 0) > 0.5 else { return }
                        panel.reveal()
                    })
    }

    func hide() {
        astronomyExpandRequested = nil
        keys.isOn = false
        completion = nil
        panel.hide()
        detail.close(animated: true)
        link?.invalidate()
        link = nil
    }
}


// Read-only smoke check of the packaged runtime, before any GUI, settings migration or AX prompt.
if CommandLine.arguments.dropFirst().first == "--astronomy-check" {
    AstronomyEngine.synchronous = true
    let query=CommandLine.arguments.dropFirst(2).joined(separator:" ")
    let answer=AstronomyEngine.shared.answer(query)
    print("Resources: " + AstronomyEngine.resource.path)
    print(answer.solution.exact)
    if let note=answer.details?.note { print(note) }
    exit((answer.details?.steps.isEmpty ?? true) ? 1 : 0)
}

Prefs.bringOver()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
