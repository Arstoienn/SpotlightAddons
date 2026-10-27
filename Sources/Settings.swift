import AppKit
import ServiceManagement
import SwiftUI

// The settings window: the pages in a sidebar of glass on the left, as in System Settings, and on
// the right the page, under a card that is the real thing in small. The card answers the setting
// the pointer is on or that was last changed, so that what a switch does is seen as it is turned.
// It is opened by Spotlight Add-ons Preferences, the app's entry for it in Spotlight's list, or by the
// gear at the foot of the panel. Each setting is kept in the defaults under the name the solver
// reads it by (Options), or the app (Prefs).
final class SettingsWindow {
    private var window: NSWindow?

    // `status` opens it on the page that says how things stand, as opening the app itself does.
    func show(status: Bool = false) {
        if status { UserDefaults.standard.set("status", forKey: "settingsPage") }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Spotlight Add-ons Preferences"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        // It has no Dock icon and is never in front by itself.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// A tap under the finger on a trackpad that has one: light for a switch or a choice, firmer for a
// change of page. Nothing happens on a Mac without.
enum Haptic {
    static func choice() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func page() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
}

// What the card at the top of the page is showing: the examples of the setting last looked at.
@Observable
final class CardPreview {
    var typed: [String] = []
    func show(_ examples: [String]) { if !examples.isEmpty, typed != examples { typed = examples } }
}

// A setting that gives a tap when it is changed, and puts its examples on the card when it is
// changed or the pointer is on it.
private struct Feel<Value: Equatable>: ViewModifier {
    let value: Value
    let examples: [String]
    @Environment(CardPreview.self) private var preview

    func body(content: Content) -> some View {
        content
            .onChange(of: value) {
                Haptic.choice()
                preview.show(examples)
            }
            .onHover { if $0 { preview.show(examples) } }
    }
}

private extension View {
    func feel<Value: Equatable>(_ value: Value, showing examples: [String] = []) -> some View {
        modifier(Feel(value: value, examples: examples))
    }
}

private struct SettingsPage: Identifiable {
    let id: String
    let title: String
    let symbol: String
    // What the card shows when the page is opened, before anything is touched.
    let examples: [String]
}

struct SettingsView: View {
    private static let pages = [
        SettingsPage(id: "status", title: "Status", symbol: "checkmark.seal", examples: []),
        SettingsPage(id: "general", title: "General", symbol: "gearshape", examples: []),
        SettingsPage(id: "answers", title: "Calculation", symbol: "equal.square", examples: ["sin(x)=0.5", "1/3+0.5*sqrt(2)", "10/4"]),
        SettingsPage(id: "cards", title: "Cards", symbol: "rectangle.stack", examples: ["12*3+4", "5 km to miles", "x^2>4"]),
        SettingsPage(id: "constants", title: "Constants", symbol: "atom", examples: ["h=0.5g*3^2", "2g=10", "F=G*5*6/2^2"]),
        SettingsPage(id: "copying", title: "Clipboard", symbol: "doc.on.clipboard", examples: ["10/4"]),
    ]
    // The page last looked at, kept for the next time.
    @AppStorage("settingsPage") private var page = "status"
    @State private var preview = CardPreview()

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<String?>(get: { page }, set: { if let chosen = $0 { page = chosen } })) {
                ForEach(Self.pages) { entry in
                    Label(entry.title, systemImage: entry.symbol).tag(entry.id)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(spacing: 0) {
                if !preview.typed.isEmpty {
                    LiveCard(typed: preview.typed)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .transition(.opacity)
                }
                Group {
                    switch page {
                    case "general": GeneralSettings()
                    case "cards": CardsSettings()
                    case "constants": ConstantsSettings()
                    case "copying": CopyingSettings()
                    case "answers": AnswersSettings()
                    default: StatusSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(Self.pages.first { $0.id == page }?.title ?? "")
        }
        .toolbar(removing: .sidebarToggle)
        .environment(preview)
        .frame(width: 780, height: 560)
        .onAppear { preview.typed = Self.pages.first { $0.id == page }?.examples ?? [] }
        .onChange(of: page) {
            Haptic.page()
            withAnimation(.smooth(duration: 0.2)) { preview.typed = Self.pages.first { $0.id == page }?.examples ?? [] }
        }
    }
}

// The card: what is typed, and what Spotlight Add-ons puts above Spotlight for it, with the settings
// as they stand. It is made again when any of them changes, so that turning one off is seen to take
// the card away.
private struct LiveCard: View {
    let typed: [String]
    @State private var changes = 0

    var body: some View {
        _ = changes
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(typed, id: \.self) { line in
                let answer = Solver.solve(line)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 190, alignment: .leading)
                        .lineLimit(1)
                    if let answer {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(answer.exact).font(.title3.weight(.medium)).lineLimit(2)
                            if let approx = answer.approx { Text(approx).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    } else {
                        Text("No card").font(.callout).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.smooth(duration: 0.2), value: typed)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in changes += 1 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of the card")
    }
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
    "degrees": false, "figures": 6, "exact": true, "decimalFirst": true, "arithmetic": true, "numberFacts": true, "paths": true, "conversions": true,
    "basePrefix": false, "inequalities": true, "algebra": true, "matrices": true, "constant.g": true, "constant.G": true,
    "constant.c": true, "precise": false, "constantValue.g": 0.0, "constantValue.G": 0.0, "constantValue.c": 0.0, "copyAsShown": false, "copyLatex": true, "returnCopies": true, "log": false, "welcome": true,
]

// What a setting does, under it.
private func note(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

// A switch, with what it does; its examples are shown on the card.
private struct CardToggle: View {
    let title: String
    @Binding var isOn: Bool
    let detail: String
    var examples: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn).feel(isOn, showing: examples)
            note(detail)
        }
        .padding(.vertical, 2)
    }
}

// How things stand now: whether it can read Spotlight, whether it opens at login, and where the
// rates of money, coins and metals are. It is made again every two seconds, so that granting the
// permission in System Settings is seen to take.
struct StatusSettings: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Form {
                Section("Spotlight Add-ons \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    let allowed = AXIsProcessTrusted()
                    row(allowed ? .good : .bad, "Reading Spotlight",
                        allowed ? "Allowed: the card comes up as it is typed." : "Not allowed: without Accessibility, nothing can be read of what is typed.")
                    if !allowed {
                        Button("Open Accessibility in System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                    let login = SMAppService.mainApp.status == .enabled
                    row(login ? .good : .neutral, "Open at login", login ? "On: it is running after the Mac is restarted." : "Off: it has to be opened again after the Mac is restarted.")
                }
                Section("Rates") {
                    ForEach(Rates.Group.allCases, id: \.self) { group in
                        let state = Rates.state(group)
                        let when = state.recorded.map(Currency.stamp)
                        row(state.offline ? .bad : state.recorded == nil ? .neutral : .good,
                            group == .fiat ? "Currencies" : group == .crypto ? "Coins" : group == .moreCrypto ? "Other coins" : "Metals",
                            state.offline ? (when.map { "No connection: the rates of \($0) are used." } ?? "No connection, and none saved.")
                                          : (when.map { "Live. Recorded \($0), from \(group.source)." } ?? "Not fetched yet: they are asked for when money is typed."))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { Rates.refresh() }
    }

    private enum Mark { case good, bad, neutral }

    private func row(_ mark: Mark, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: mark == .good ? "checkmark.circle.fill" : mark == .bad ? "exclamationmark.triangle.fill" : "circle.dashed")
                .foregroundStyle(mark == .good ? Color.green : mark == .bad ? Color.orange : Color.secondary)
                .font(.system(size: 16))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct AnswersSettings: View {
    @AppStorage("degrees") private var degrees = false
    @AppStorage("figures") private var figures = 6
    @AppStorage("exact") private var exact = true
    @AppStorage("decimalFirst") private var decimalFirst = true

    var body: some View {
        Form {
            Section("Angles") {
                Picker("Angles are in", selection: $degrees) {
                    Text("Radians").tag(false)
                    Text("Degrees").tag(true)
                }
                .pickerStyle(.segmented)
                .feel(degrees, showing: ["sin(x)=0.5", "sin(30°)"])
                note(degrees ? "An angle marked rad, or with π in it, is still in radians: sin(x rad), sin(π/6)."
                             : "An angle marked deg or ° is in degrees: sin(x deg), cos(35°).")
            }
            Section("Numbers") {
                Picker("Significant figures", selection: $figures) {
                    ForEach(3...10, id: \.self) { Text("\($0)").tag($0) }
                }
                .feel(figures, showing: ["1/3+0.5*sqrt(2)"])
                note("How far a decimal is carried. Six is what a calculator shows; three is what an answer is usually asked to.")

                Toggle("Exact answers where there are any", isOn: $exact)
                    .feel(exact, showing: ["2n^2=10", "sqrt(8)"])
                note("Fractions, roots and π where they are exact; otherwise decimals only.")

                Toggle("Decimals before fractions in a sum", isOn: $decimalFirst)
                    .disabled(!exact)
                    .feel(decimalFirst, showing: ["10/4", "1/3+1/6"])
                note(decimalFirst ? "A sum is answered as a decimal first, with the fraction beneath it."
                                  : "A sum is answered as a fraction first, with the decimal beneath it.")
            }
        }
        .formStyle(.grouped)
    }
}

struct CardsSettings: View {
    @AppStorage("arithmetic") private var arithmetic = true
    @AppStorage("numberFacts") private var numberFacts = true
    @AppStorage("paths") private var paths = true
    @AppStorage("conversions") private var conversions = true
    @AppStorage("basePrefix") private var basePrefix = false
    @AppStorage("inequalities") private var inequalities = true
    @AppStorage("algebra") private var algebra = true
    @AppStorage("matrices") private var matrices = true

    var body: some View {
        Form {
            Section("Typed with no equals sign") {
                CardToggle(title: "Arithmetic", isOn: $arithmetic,
                           detail: "Turn this off if Spotlight's own calculator is on, or the two will both answer. A name still works: x = 12*3+4.",
                           examples: ["12*3+4", "5!/(3!2!)"])
                CardToggle(title: "A number by itself", isOn: $numberFacts,
                           detail: "Every number typed into Spotlight brings up a card when this is on, a year among them.",
                           examples: ["2048", "0.375"])
                CardToggle(title: "A path to a file or folder", isOn: $paths,
                           detail: "Names the file, and shows it in Finder when the card is clicked, or Return is pressed with the pointer on it. Only a path that exists brings up a card.",
                           examples: ["/usr/bin"])
            }
            Section("Units and bases") {
                CardToggle(title: "Units and number bases", isOn: $conversions,
                           detail: "A quantity and a unit known to the calculator, and a unit of the same kind to convert to.",
                           examples: ["5 km to miles", "255 in hex"])
                CardToggle(title: "Mark a base with its prefix", isOn: $basePrefix,
                           detail: "The prefix is always understood when typed: 0xFF + 1 is 256.",
                           examples: ["3 in binary", "255 in hex"])
            }
            Section("Algebra and calculus") {
                CardToggle(title: "Inequalities", isOn: $inequalities,
                           detail: "In one letter: polynomials, and abs, exp and the like. Several taken together with && and ||.",
                           examples: ["x^2>4", "1<x<5"])
                CardToggle(title: "Algebra by name", isOn: $algebra,
                           detail: "Nothing is done to an expression unless it is asked for by name. Includes limits and trigonometric identities.",
                           examples: ["expand((x+1)^2)", "integrate(x^2, 0, 1)", "sin(x)^2+cos(x)^2"])
                CardToggle(title: "Matrices and vectors", isOn: $matrices,
                           detail: "Determinants, inverses, products, dot and cross products.",
                           examples: ["det([[1,2],[3,4]])"])
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

    // What each constant is shown working in.
    private static let examples = ["g": ["h=0.5g*3^2", "2g=10"], "G": ["F=G*5*6/2^2"], "c": ["9e16=!c^2"]]

    var body: some View {
        let _ = (gValue, bigGValue, cValue, customRaw, precise)
        Form {
            Section {
                ForEach(Array(Constants.table.enumerated()), id: \.offset) { index, row in
                    let isOn = [$g, $bigG, $c][index]
                    let value = Constants.chosen(row.name)?.value ?? 0
                    ConstantRow(name: row.name, title: row.title, value: value, unit: Text(Constants.units[row.name] ?? ""), isOn: isOn,
                                presets: Constants.presets[row.name] ?? []) { typed in
                        let usual = precise ? row.precise.value : row.booklet.value
                        if let typed, typed != usual { UserDefaults.standard.set(typed, forKey: "constantValue." + row.name) }
                        else { UserDefaults.standard.removeObject(forKey: "constantValue." + row.name) }
                    }
                    .feel(value, showing: Self.examples[row.name] ?? [])
                    .feel(isOn.wrappedValue, showing: Self.examples[row.name] ?? [])
                }
                ForEach(Constants.custom) { constant in
                    let isOn = Binding(get: { constant.off != true }, set: { on in update(constant.name) { $0.off = on ? nil : true } })
                    ConstantRow(name: constant.name, title: nil, value: constant.value, unit: Text(constant.unit), isOn: isOn,
                                remove: { Constants.custom.removeAll { $0.name == constant.name } }) { typed in
                        if let typed { update(constant.name) { $0.value = typed } }
                    }
                    .feel(constant, showing: ["x=2*\(constant.name)"])
                }
                AddConstantRow()
            } header: {
                Text("Constants")
            } footer: {
                note("A letter is taken as its constant only where the equation has another letter to be solved for: h = 0.5g·3² uses g, whereas 2g = 10 is solved for g. A ! before the letter reverses this. Clearing the value of g, G or c restores the usual one.")
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

struct CopyingSettings: View {
    @AppStorage("copyAsShown") private var copyAsShown = false
    @AppStorage("copyLatex") private var copyLatex = true
    @AppStorage("returnCopies") private var returnCopies = true

    var body: some View {
        Form {
            Section("What is copied") {
                Picker("The copy button copies", selection: $copyAsShown) {
                    Text("A decimal: 2.5").tag(false)
                    Text("The answer as shown: 5/2").tag(true)
                }
                .pickerStyle(.radioGroup)
                .feel(copyAsShown)
                note("A decimal is what another program can read, and is given to twelve figures whatever is chosen on the Calculation page. Several answers are copied with commas between: 2, 3.")
            }
            Section("The panel") {
                Picker("A line of the working copies", selection: $copyLatex) {
                    Text("LaTeX: \\frac{5}{2}").tag(true)
                    Text("The line as shown: 5/2").tag(false)
                }
                .pickerStyle(.radioGroup)
                .feel(copyLatex)
                note("Click a line of the working or the solutions to copy it; right-click it for the other. The first line is what was typed, as it was read.")
            }
            Section("Return") {
                Toggle("Return copies, while the pointer is on the card", isOn: $returnCopies)
                    .feel(returnCopies)
                note("With the pointer anywhere else, Return is Spotlight's and opens what is chosen in its list.")
            }
            Section("Afterwards") {
                note("What is copied becomes ans, for the next sum: ans*2. Where there were several answers they are ans1, ans2 and so on. clip is the number on the clipboard: 20*clip.")
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @State private var resetting = false
    @AppStorage("log") private var log = false
    @AppStorage("welcome") private var welcome = true
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?

    var body: some View {
        Form {
            Section("Starting") {
                Toggle("Open at login", isOn: $atLogin)
                    .feel(atLogin)
                    .onChange(of: atLogin) { _, wanted in
                        do {
                            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginProblem = nil
                        } catch {
                            loginProblem = error.localizedDescription
                            atLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                note(loginProblem ?? "Without this, Spotlight Add-ons has to be opened again after the Mac is restarted.")

                Toggle("Show a note when it is opened", isOn: $welcome)
                    .feel(welcome)
                note("A moment's note at the top of the screen that Spotlight Add-ons is running, since it has no window. It says so too when the permission it needs has not been given.")
            }
            Section("Troubleshooting") {
                Toggle("Keep a log", isOn: $log)
                    .feel(log)
                note("When the card came and went, and why, in ~/Library/Logs/SpotlightAddons.log: for finding out why a card went missing. It has how many characters were typed and never what they were.")
                Button("Show the log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/SpotlightAddons.log")])
                }
                .disabled(!FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Logs/SpotlightAddons.log"))
            }
            Section("Spotlight Add-ons \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                HStack {
                    Button("Reset every setting…") { resetting = true }
                    Spacer()
                    Button("Quit Spotlight Add-ons") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset every setting?", isPresented: $resetting) {
            Button("Reset", role: .destructive) { for key in defaultSettings.keys { UserDefaults.standard.removeObject(forKey: key) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The choices on every page go back to what they were when Spotlight Add-ons was first opened. Nothing else is touched.")
        }
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
