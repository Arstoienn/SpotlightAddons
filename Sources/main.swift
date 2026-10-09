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
    let returnKey = ReturnKey()
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

    // ans. The answer showing becomes ans when it is done with: copied, cleared, or Spotlight
    // closed on it. Until something else is typed, that same text still reads ans as it was
    // before, so that ans+1 does not climb each time it is looked at again.
    var shown: String?         // the text the card last answered
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

    // One of the app's own entries, chosen in Spotlight's list.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard let entry = Entry.chosen(userActivity) else { return false }
        switch entry {
        case .clipboardHistory: ClipboardHistory.open()
        case .settings: settings.show()
        }
        Entry.index()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsButton.open = { [weak self] in self?.settings.show() }
        // Opened by hand, it shows its preferences; opened by the login, it keeps quiet but for its note.
        let launch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: 0x70726474)   // 'prdt'
        let atLogin = launch?.enumCodeValue == 0x6C676974                                                   // 'lgit'
        if !atLogin { DispatchQueue.main.async { [weak self] in self?.settings.show(status: true) } }
        Entry.index()
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
        watcher.onChange = { [weak self] text in self?.update(text) }
        panel.onHover = { [weak self] in self?.expand() }
        Copying.shared.text = { [weak self] in self.flatMap { Solver.copy($0.text) } }
        Copying.shared.copied = { [weak self] in self?.remember() }
        Copying.shared.go = { [weak self] in self.flatMap { Location.parse($0.text) }?.show() }
        // Return copies only with the pointer resting on the card or its panel.
        returnKey.take = { [weak self] in
            guard let self, panel.isVisible else { return false }
            guard Prefs.returnCopies, detail.isOpen || panel.frame.contains(NSEvent.mouseLocation) else { return false }
            return Copying.shared.copy()
        }
        // Rates come in after the card was made from the last had, or the connection is found
        // lost: the card is made again, if it is money that is showing.
        NotificationCenter.default.addObserver(forName: Rates.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self, panel.isVisible, !detail.isOpen, Currency.conversion(text) != nil else { return }
            _ = present()
        }
        watcher.start()
    }

    func update(_ text: String) {
        // Typing on while the panel is open puts the panel away; the card follows what is typed.
        if detail.isOpen {
            guard text != self.text else { return }
            detail.close(animated: false)
        }
        // Spotlight says the field has changed several times for each key; once is enough.
        if text == self.text, panel.isVisible { return }
        if text.isEmpty { remember() }
        self.text = text
        typed += 1
        Memory.answers = text == remembered ? ansBefore : ansNow
        // The clipboard is only read when it is asked for by name.
        if text.contains("clip") {
            let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            Memory.clip = copied.flatMap { Double($0.replacingOccurrences(of: "−", with: "-")) }
        }
        guard Solver.solve(text) != nil else {
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
        guard let solution = Solver.solve(text), let geometry = watcher.geometry(),
              (SpotlightWatcher.alpha() ?? 0) > 0
        else { return false }
        placement = geometry.placement
        spotlight = geometry.window
        // Everything has an answer to copy but a number typed by itself. (Working out what the
        // answer is waits until it is asked for: this runs at every keystroke.)
        let place = Location.parse(text)
        Copying.shared.isPlace = place != nil
        Copying.shared.symbol = place.map { $0.isFolder ? "folder" : "doc" } ?? "function"
        Copying.shared.available = Copying.shared.isPlace || NumberFacts.parse(Latex.plain(text)) == nil
        shown = text
        panel.show(solution, window: geometry.window)
        returnKey.isOn = true
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
    func expand() {
        // Not while Spotlight is being dragged, or has only just been put down.
        guard Date().timeIntervalSince(lastMove) > 0.3 else { return }
        guard !detail.isOpen, let answer = Solver.solve(text), let details = Solver.details(text) else { return }
        detail.show(answer, details, from: panel.frame, level: panel.level,
                    onCovered: { [weak self] in self?.panel.conceal() },
                    onCollapsed: { [weak self] in
                        guard let self, (SpotlightWatcher.alpha() ?? 0) > 0.5 else { return }
                        panel.reveal()
                    })
    }

    func hide() {
        returnKey.isOn = false
        panel.hide()
        detail.close(animated: true)
        link?.invalidate()
        link = nil
    }
}

// Its entries taken out of Spotlight's list again, for when the app is to be removed:
//     "/Applications/Spotlight Add-ons.app/Contents/MacOS/SpotlightAddons" --forget-entries
if CommandLine.arguments.contains("--forget-entries") { Entry.forget() }

Prefs.bringOver()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
