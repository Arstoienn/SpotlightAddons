import AppKit
import ServiceManagement
import SwiftUI

// The settings window: four pages, each a button in the toolbar, as a Mac's settings windows have
// them. General says how things stand and what the app does on opening; Answers is how an answer
// is written and copied; Cards is what brings a card up; Constants is the letters that stand for
// numbers. Each setting has a short label and, under it, one line: what is typed, or what the
// switch does. It is opened by opening the app itself, from Spotlight or Finder, or by the gear
// at the foot of the panel. Each setting is kept in the defaults under the name the solver reads
// it by (Options), or the app (Prefs).
final class SettingsWindow {
    private var window: NSWindow?
    private var pages: SettingsPages?

    // `status` opens it on the page that says how things stand, as opening the app itself does.
    func show(status: Bool = false) {
        if window == nil {
            let pages = SettingsPages()
            let window = NSWindow(contentViewController: pages)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.pages = pages
            self.window = window
        }
        if status { pages?.show("general") }
        // It has no Dock icon and is never in front by itself.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// The pages, a toolbar button each; the window is as tall as the page chosen, and a page longer
// than the screen allows is scrolled.
final class SettingsPages: NSTabViewController {
    static let width: CGFloat = 640

    private static let pages: [(id: String, title: String, symbol: String, height: CGFloat, view: AnyView)] = [
        ("general", "General", "gearshape", 660, AnyView(GeneralSettings())),
        ("answers", "Answers", "equal.square", 600, AnyView(AnswersSettings())),
        ("cards", "Cards", "rectangle.stack", 400, AnyView(CardsSettings())),
        ("constants", "Constants", "atom", 450, AnyView(ConstantsSettings())),
    ]

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []   // a page is shown at once, not drawn in
        for page in Self.pages {
            let hosting = NSHostingController(rootView: page.view.frame(width: Self.width, height: page.height))
            hosting.sizingOptions = []
            hosting.title = page.title   // the window's title, as the page chosen
            hosting.preferredContentSize = NSSize(width: Self.width, height: page.height)
            let item = NSTabViewItem(viewController: hosting)
            item.identifier = page.id
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            addTabViewItem(item)
        }
        // The page last looked at, kept for the next time; what a version with other pages kept is
        // the page its settings are on now.
        show(UserDefaults.standard.string(forKey: "settingsPage") == "copying" ? "answers" : UserDefaults.standard.string(forKey: "settingsPage") ?? "general")
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ id: String) {
        selectedTabViewItemIndex = Self.pages.firstIndex { $0.id == id } ?? 0
    }

    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        if let id = item?.identifier as? String { UserDefaults.standard.set(id, forKey: "settingsPage") }
    }
}

// A light tap under the finger on a trackpad that has one, given once when a switch is turned or
// one of two choices is taken, and for nothing else: not a change of page, not the pointer moving,
// not a menu, not a setting put back by Reset. Nothing happens on a Mac without.
enum Haptic {
    static func choice() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
}

// A setting as its control is to change it: with a tap when the hand changes it, and only then.
private func tapped<Value: Equatable>(_ setting: Binding<Value>) -> Binding<Value> {
    Binding(get: { setting.wrappedValue }, set: { new in
        if new != setting.wrappedValue { Haptic.choice() }
        setting.wrappedValue = new
    })
}

// What the app itself does or leaves alone. The solver's own choices are in Options.
enum Prefs {
    private static func flag(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }

    static var returnCopies: Bool { flag("returnCopies", true) }
    static var copyLatex: Bool { flag("copyLatex", true) }   // a click on a line of the panel copies its LaTeX
    static var log: Bool { flag("log", false) }
    static var welcome: Bool { flag("welcome", true) }

    // The app was Spotlight Solve (com.arstoienn.spotlight-solve) and then Spotlight Plus
    // (com.arstoienn.spotlight-plus) before it was Spotlight Add-ons. What was chosen and
    // remembered under those names is brought over, the once, the later name's first.
    static func bringOver() {
        let before = ["com.arstoienn.spotlight-plus", "com.arstoienn.spotlight-solve"], defaults = UserDefaults.standard
        guard defaults.object(forKey: "broughtOver") == nil else { return }
        for id in before where id != Bundle.main.bundleIdentifier {
            for (key, value) in defaults.persistentDomain(forName: id) ?? [:] where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "broughtOver")
    }
}

// What is kept, and what it was before anything was chosen.
private let defaultSettings: [String: Any] = [
    "degrees": false, "figures": 6, "exact": true, "decimalFirst": true, "arithmetic": true, "paths": true, "commands": false, "commandReturn": true,
    "basePrefix": false, "constant.g": true, "constant.G": true,
    "constant.c": true, "precise": false, "constantValue.g": 0.0, "constantValue.G": 0.0, "constantValue.c": 0.0, "copyAsShown": false, "copyLatex": true, "returnCopies": true, "log": false, "welcome": true,
]

// A line under a setting or a section: what it does, in a sentence.
private func note(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

// The name of a setting and, under it, one line: what is typed for it, as it is typed, and where
// it is wanted a sentence on what the setting does.
private struct RowLabel: View {
    let title: String
    var typed: String? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let typed { Text(typed).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
            if let detail { note(detail) }
        }
    }
}

// A switch with its line, and a tap when it is turned.
private struct Switch: View {
    let title: String
    var typed: String? = nil
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: tapped($isOn)) { RowLabel(title: title, typed: typed, detail: detail) }
    }
}

// How things stand, and what the app does of itself: whether it can read Spotlight, opening at
// login, the note on opening, where the rates of money, coins and metals are, and the log. What
// is found out rather than chosen is looked at again every two seconds, so that granting the
// permission in System Settings is seen to take.
struct GeneralSettings: View {
    @AppStorage("log") private var log = false
    @AppStorage("welcome") private var welcome = true
    @State private var allowed = AXIsProcessTrusted()
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?
    @State private var looked = 0
    @State private var resetting = false
    @State private var allAsked: Date?   // when Refresh All was clicked
    private let clock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private static let logFile = NSHomeDirectory() + "/Library/Logs/SpotlightAddons.log"

    var body: some View {
        let _ = looked
        Form {
            Section {
                if allowed {
                    LabeledContent {
                        Text("Allowed").foregroundStyle(.secondary)
                    } label: {
                        Label { Text("Reading Spotlight") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    LabeledContent {
                        Button("Open System Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    } label: {
                        Label {
                            RowLabel(title: "Accessibility permission is required", detail: "Without it, nothing typed into Spotlight can be read.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
            }
            Section("Startup") {
                Toggle(isOn: Binding(get: { atLogin }, set: openAtLogin)) {
                    RowLabel(title: "Open at login", detail: loginProblem)
                }
                Switch(title: "Show a note on opening", detail: "A brief note confirms that the app is running, as it has no window.", isOn: $welcome)
            }
            Section {
                ForEach(Rates.Group.allCases, id: \.self) { group in RateRow(group: group, allAsked: allAsked) }
            } header: {
                HStack {
                    Text("Exchange rates")
                    Spacer()
                    Button("Refresh All") {
                        allAsked = Date()
                        Rates.refresh(force: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { looked += 1 }
                    }
                        .buttonStyle(.borderless)
                        .disabled(Rates.isRefreshing)
                }
            }
            Section("Troubleshooting") {
                Switch(title: "Keep a log", detail: "Records when a card appeared and why, never what was typed. A crash is always recorded, and a notification says so.", isOn: $log)
                LabeledContent("SpotlightAddons.log") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Self.logFile)]) }
                        .disabled(!FileManager.default.fileExists(atPath: Self.logFile))
                }
            }
            Section {
                LabeledContent("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    HStack {
                        Button("Reset All Settings…") { resetting = true }
                        Button("Quit") { NSApp.terminate(nil) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { Rates.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Rates.changed)) { _ in looked += 1 }
        .onReceive(clock) { _ in
            allowed = AXIsProcessTrusted()
            atLogin = SMAppService.mainApp.status == .enabled
            looked += 1
        }
        .alert("Reset all settings?", isPresented: $resetting) {
            Button("Reset", role: .destructive) { for key in defaultSettings.keys { UserDefaults.standard.removeObject(forKey: key) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The choices on every page return to what they were when Spotlight Add-ons was first opened. Constants that were added are kept.")
        }
    }

    // Asked of the system, and shown as the system then has it: a refusal leaves the switch where it was.
    private func openAtLogin(_ wanted: Bool) {
        do {
            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginProblem = nil
        } catch {
            loginProblem = error.localizedDescription
        }
        let now = SMAppService.mainApp.status == .enabled
        if now != atLogin { Haptic.choice() }
        atLogin = now
    }
}

// One source of exchange rates on one line: whether it is up to date, when it was last updated,
// and a button to update it now. What it covers, where it comes from and why an update failed are
// in its tooltip.
private struct RateRow: View {
    let group: Rates.Group
    var allAsked: Date?
    // A refresh asked for here: the spinner is shown for at least a moment, however quickly the
    // rates come, so that the click is seen to have done something.
    @State private var asked: Date?
    @State private var tick = 0

    // 01:02 for today, 10 Nov for another day, and "just now" within the minute.
    private static func when(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM"
        return f.string(from: date)
    }

    var body: some View {
        let _ = tick
        let state = Rates.state(group)
        let busy = state.updating || [asked, allAsked].compactMap { $0 }.contains { Date().timeIntervalSince($0) < 0.7 }
        let fresh = state.recorded.map { Date().timeIntervalSince($0) < 60 } ?? false
        let status = busy ? "Updating…"
            : state.offline ? "Update failed" + (state.recorded.map { ", using rates from " + Self.when($0) } ?? "")
            : state.recorded.map { "Updated " + Self.when($0) } ?? "Not yet downloaded"
        HStack(spacing: 8) {
            Image(systemName: state.offline ? "exclamationmark.triangle.fill" : state.recorded == nil ? "circle.dashed" : "checkmark.circle.fill")
                .foregroundStyle(state.offline ? Color.orange : state.recorded == nil ? Color.secondary : Color.green)
            Text(group.title)
            Spacer()
            Text(status)
                .foregroundStyle(!busy && fresh && !state.offline ? Color.green : Color.secondary)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: status)
            ZStack {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Update now")
                }
            }
            .frame(width: 18)
        }
        .help([group.explanation, "Source: " + group.source, state.error].compactMap { $0 }.joined(separator: "\n"))
    }

    private func refresh() {
        asked = Date()
        Rates.refresh(group, force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { tick += 1 }
    }
}

// How an answer is written, and what is put on the clipboard.
struct AnswersSettings: View {
    @AppStorage("degrees") private var degrees = false
    @AppStorage("figures") private var figures = 6
    @AppStorage("exact") private var exact = true
    @AppStorage("decimalFirst") private var decimalFirst = true
    @AppStorage("basePrefix") private var basePrefix = false
    @AppStorage("copyAsShown") private var copyAsShown = false
    @AppStorage("copyLatex") private var copyLatex = true
    @AppStorage("returnCopies") private var returnCopies = true

    var body: some View {
        Form {
            Section {
                Picker(selection: tapped($degrees)) {
                    Text("Radians").tag(false)
                    Text("Degrees").tag(true)
                } label: {
                    RowLabel(title: "Angles", detail: degrees ? "An angle marked rad, or containing π, remains in radians."
                                                              : "An angle marked deg or ° remains in degrees.")
                }
                .pickerStyle(.segmented)
            }
            Section("Numbers") {
                Picker("Significant figures", selection: $figures) {
                    ForEach(3...10, id: \.self) { Text("\($0)").tag($0) }
                }
                Switch(title: "Exact answers", detail: "Fractions, roots and π are kept where the answer is exact: 5/2, √5, π/6.", isOn: $exact)
                Picker(selection: tapped($decimalFirst)) {
                    Text("Decimal").tag(true)
                    Text("Fraction").tag(false)
                } label: {
                    RowLabel(title: "A sum is shown first as", detail: decimalFirst ? "10/4 gives 2.5, with 5/2 beneath." : "10/4 gives 5/2, with 2.5 beneath.")
                }
                .pickerStyle(.segmented)
                .disabled(!exact)
                Switch(title: "Prefix on a number base", detail: "255 in hex gives 0xFF rather than FF.", isOn: $basePrefix)
            }
            Section {
                Picker("The copy button copies", selection: $copyAsShown) {
                    Text("A decimal: 2.5").tag(false)
                    Text("The answer as shown: 5/2").tag(true)
                }
                Picker(selection: $copyLatex) {
                    Text("LaTeX: \\frac{5}{2}").tag(true)
                    Text("The line as shown: 5/2").tag(false)
                } label: {
                    RowLabel(title: "A line of the working copies", detail: "A right-click copies the other form.")
                }
                Switch(title: "Return copies the answer", detail: "Applies while the pointer is on the card; elsewhere Return remains Spotlight's.", isOn: $returnCopies)
            } header: {
                Text("Copying")
            } footer: {
                note("A copied answer becomes ans in the next calculation, and clip is the number on the clipboard: ans*2, 20*clip.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

// What brings up a card where it might not be wanted: arithmetic, which Spotlight answers too, and
// a path or a command. Everything else typed that is mathematics always has its card.
struct CardsSettings: View {
    @AppStorage("arithmetic") private var arithmetic = true
    @AppStorage("paths") private var paths = true
    @AppStorage("commands") private var commands = false
    @AppStorage("commandReturn") private var commandReturn = true

    var body: some View {
        Form {
            Section {
                Switch(title: "Arithmetic", typed: "12*3+4", detail: "Spotlight's own calculator answers this as well. When off, only Spotlight's answer is shown.", isOn: $arithmetic)
            } header: {
                Text("Spotlight's calculator")
            }
            Section("Files and Terminal") {
                Switch(title: "A path to a file or folder", typed: "/usr/bin", detail: "A click, or Return with the pointer on the card, shows it in Finder.", isOn: $paths)
                Switch(title: "A command for Terminal", typed: "> top", detail: "The command is typed in a new Terminal window and is not run until Return is pressed there.", isOn: $commands)
                Switch(title: "Return types the command from anywhere", detail: "When off, Return does so only with the pointer on the card.", isOn: $commandReturn)
                    .disabled(!commands)
            }
        }
        .formStyle(.grouped)
    }
}

// Every constant on one row: its letter, its value, which may be typed over, its unit, and a
// switch. g is 10 by typing 10; a constant of one's own is added on the last row.
struct ConstantsSettings: View {
    @AppStorage("constant.g") private var g = true
    @AppStorage("constant.G") private var bigG = true
    @AppStorage("constant.c") private var c = true
    // Read only to be told of a change: the values are Options.value and Constants.custom.
    @AppStorage("constantValue.g") private var gValue = 0.0
    @AppStorage("constantValue.G") private var bigGValue = 0.0
    @AppStorage("constantValue.c") private var cValue = 0.0
    @AppStorage("customConstants") private var customRaw = ""
    @AppStorage("precise") private var precise = false

    var body: some View {
        let _ = (gValue, bigGValue, cValue, customRaw, precise)
        Form {
            Section {
                ForEach(Array(Constants.table.enumerated()), id: \.offset) { index, row in
                    let value = Constants.chosen(row.name)?.value ?? 0
                    ConstantRow(name: row.name, title: row.title, value: value, unit: Text(Constants.units[row.name] ?? ""), isOn: tapped([$g, $bigG, $c][index]),
                                presets: Constants.presets[row.name] ?? []) { typed in
                        let usual = precise ? row.precise.value : row.booklet.value
                        if let typed, typed != usual { UserDefaults.standard.set(typed, forKey: "constantValue." + row.name) }
                        else { UserDefaults.standard.removeObject(forKey: "constantValue." + row.name) }
                    }
                }
            } header: {
                Text("Physical constants")
            } footer: {
                note("A value may be typed over, and clearing it restores the usual one. A letter stands for its constant only where another letter is solved for: h\u{00A0}=\u{00A0}0.5g·3² uses g, whereas 2g\u{00A0}=\u{00A0}10 is solved for g. A ! before the letter reverses this.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Other constants") {
                ForEach(Constants.custom) { constant in
                    let isOn = Binding(get: { constant.off != true }, set: { on in update(constant.name) { $0.off = on ? nil : true } })
                    ConstantRow(name: constant.name, title: nil, value: constant.value, unit: Text(constant.unit), isOn: tapped(isOn),
                                remove: { Constants.custom.removeAll { $0.name == constant.name } }) { typed in
                        if let typed { update(constant.name) { $0.value = typed } }
                    }
                }
                AddConstantRow()
            }
        }
        .formStyle(.grouped)
    }

    private func update(_ name: String, _ change: (inout Constants.Custom) -> Void) {
        var list = Constants.custom
        guard let at = list.firstIndex(where: { $0.name == name }) else { return }
        change(&list[at])
        Constants.custom = list
    }
}

// A letter as it is written, its subscript lowered: k_e.
private func symbol(_ name: String) -> Text {
    let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
    let letter = Text(parts[0]).font(.system(.body, design: .serif).italic())
    guard parts.count == 2 else { return letter }
    return letter + Text(parts[1]).font(.system(.caption, design: .serif)).baselineOffset(-4)
}

// A value as it may be typed again: 6.67e-11, 3e8, 9.8.
private func typable(_ v: Double) -> String {
    let size = abs(v)
    guard size != 0, size < 1e-3 || size >= 1e6 else { return String(format: "%.10g", v) }
    let parts = String(format: "%.9e", v).split(separator: "e")
    var mantissa = String(parts[0])
    while mantissa.hasSuffix("0") { mantissa.removeLast() }
    if mantissa.hasSuffix(".") { mantissa.removeLast() }
    return mantissa + "e\(Int(parts[1]) ?? 0)"
}

private struct ConstantRow: View {
    let name: String
    let title: String?
    let value: Double
    let unit: Text
    @Binding var isOn: Bool
    var remove: (() -> Void)? = nil
    var presets: [(value: Double, label: String)] = []
    let commit: (Double?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            symbol(name).frame(width: 56, alignment: .leading).help(title ?? name)
            HStack(spacing: 4) {
                ValueField(value: value, commit: commit)
                // The usual values, so that none need be typed: 9.8, 9.81, 10.
                if !presets.isEmpty {
                    Menu {
                        ForEach(presets, id: \.value) { preset in
                            Button { commit(preset.value) } label: {
                                let text = "\(Constants.written(preset.value))   \(preset.label)"
                                if preset.value == value { Label(text, systemImage: "checkmark") } else { Text(text) }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("The usual values of \(name)")
                }
            }
            .frame(width: 136, alignment: .leading)
            unit.foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let remove {
                Button(action: remove) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Removes \(name)")
            }
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .opacity(isOn ? 1 : 0.5)
    }
}

// The value of a constant, kept when Return is pressed or the field is left. What is not a
// number is put back as it was; nothing at all is passed on as nil.
private struct ValueField: View {
    let value: Double
    let commit: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .frame(width: 110)
            .focused($focused)
            .onAppear { text = typable(value) }
            .onChange(of: value) { if !focused { text = typable(value) } }
            .onChange(of: focused) { _, now in if !now { save() } }
            .onSubmit(save)
    }

    private func save() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { commit(nil) } else if let v = Constants.number(typed) { commit(v) }
        text = typable(value)
    }
}

// The last row: a name, a value and a unit, and Add.
private struct AddConstantRow: View {
    @State private var name = ""
    @State private var value = ""
    @State private var unit = ""

    // The constant the fields describe, or why they do not describe one yet.
    private var entry: Result<Constants.Custom, Constants.Refusal> {
        let letter: String
        switch Constants.letter(name) {
        case .success(let l): letter = l
        case .failure(let refusal): return .failure(refusal)
        }
        if Constants.custom.contains(where: { $0.name == letter }) { return .failure(Constants.Refusal("\(letter) is already in the list.")) }
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(Constants.Refusal("")) }
        guard let v = Constants.number(value) else { return .failure(Constants.Refusal("The value is to be a number: 8.99e9, 6.022*10^23.")) }
        return .success(Constants.Custom(name: letter, value: v, unit: unit.trimmingCharacters(in: .whitespaces)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                TextField("", text: $name, prompt: Text("Name")).frame(width: 56)
                TextField("", text: $value, prompt: Text("Value")).frame(width: 110).frame(width: 136, alignment: .leading)
                TextField("", text: $unit, prompt: Text("Unit"))
                Button("Add", action: add)
                    .disabled((try? entry.get()) == nil)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .onSubmit(add)
            if !name.isEmpty, case .failure(let refusal) = entry, !refusal.reason.isEmpty {
                Text(refusal.reason).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func add() {
        guard case .success(let constant) = entry else { return }
        Constants.custom.append(constant)
        (name, value, unit) = ("", "", "")
    }
}

// The gear at the foot of the panel.
struct SettingsButton: View {
    static var open: () -> Void = {}

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "gearshape").font(.system(size: 12, weight: .medium))
            Text("Preferences").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .overlay(ClickTarget { SettingsButton.open() })
    }
}
