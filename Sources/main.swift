import AppKit
import ApplicationServices

// Spotlight Plus: type an equation into Spotlight, like "2n^2=10", and the answer appears on a
// card above it as you type, the way Spotlight's own calculator answers "2+2". It runs in the
// background with no window or Dock icon, and reads Spotlight's search field through
// Accessibility.

final class AppDelegate: NSObject, NSApplicationDelegate {
    let watcher = SpotlightWatcher()
    let panel = ResultPanel()
    let detail = DetailPanel()
    let returnKey = ReturnKey()
    let settings = SettingsWindow()
    var clipboardAsked = Date.distantPast
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
    var ansBefore: Double?     // what ans was until then
    var ansNow: Double? = UserDefaults.standard.object(forKey: "ans") as? Double

    // Opened while already running, which is what choosing it in Spotlight does: the settings.
    // Choosing Clipboard History there may open the app in passing as well; that is not this,
    // so a moment is given for it to say which it was.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, Date().timeIntervalSince(clipboardAsked) > 2 else { return }
            settings.show()
        }
        return false
    }

    // Clipboard History, chosen in Spotlight's list.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        guard ClipboardHistory.chosen(userActivity) else { return false }
        clipboardAsked = Date()
        ClipboardHistory.open()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsButton.open = { [weak self] in self?.settings.show() }
        ClipboardHistory.index()
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            start()
        } else {
            // Wait for the permission rather than asking to be opened again once it is given.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.start()
            }
        }
    }

    func start() {
        watcher.onChange = { [weak self] text in self?.update(text) }
        panel.onHover = { [weak self] in self?.expand() }
        Copying.shared.text = { [weak self] in self.flatMap { Solver.copy($0.text) } }
        Copying.shared.copied = { [weak self] in self?.remember() }
        // Return copies only with the pointer resting on the card or its panel.
        returnKey.take = { [weak self] in
            guard let self, panel.isVisible else { return false }
            guard Prefs.returnCopies, detail.isOpen || panel.frame.contains(NSEvent.mouseLocation) else { return false }
            return Copying.shared.copy()
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
        Memory.ans = text == remembered ? ansBefore : ansNow
        // The clipboard is only read when it is asked for by name.
        if text.contains("clip") {
            let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
            Memory.clip = copied.flatMap { Double($0.replacingOccurrences(of: "−", with: "-")) }
        }
        guard Solver.solve(text) != nil else {
            Log.note("typed \(text.count) characters: nothing to show")
            return hide()
        }
        if present() { Log.note("typed \(text.count) characters: shown") } else { lost("no place for the card as it was typed") }
    }

    // The answer showing becomes ans.
    func remember() {
        guard let shown, shown != remembered else { return }
        Memory.ans = ansNow
        guard let value = Solver.value(shown) else { return }
        (ansBefore, ansNow, remembered) = (ansNow, value, shown)
        UserDefaults.standard.set(value, forKey: "ans")
        Memory.ans = text == remembered ? ansBefore : ansNow
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
        Copying.shared.available = NumberFacts.parse(Latex.plain(text)) == nil
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
