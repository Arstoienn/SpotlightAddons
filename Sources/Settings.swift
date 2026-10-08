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

    func show() {
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
        SettingsPage(id: "general", title: "General", symbol: "gearshape", examples: []),
        SettingsPage(id: "answers", title: "Calculation", symbol: "equal.square", examples: ["sin(x)=0.5", "1/3+0.5*sqrt(2)", "10/4"]),
        SettingsPage(id: "cards", title: "Cards", symbol: "rectangle.stack", examples: ["12*3+4", "5 km to miles", "x^2>4"]),
        SettingsPage(id: "constants", title: "Constants", symbol: "atom", examples: ["h=0.5g*3^2", "2g=10", "F=G*5*6/2^2"]),
        SettingsPage(id: "copying", title: "Clipboard", symbol: "doc.on.clipboard", examples: ["10/4"]),
    ]
    // The page last looked at, kept for the next time.
    @AppStorage("settingsPage") private var page = "general"
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
                    case "cards": CardsSettings()
                    case "constants": ConstantsSettings()
                    case "copying": CopyingSettings()
                    case "general": GeneralSettings()
                    default: AnswersSettings()
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
    "constant.c": true, "precise": false, "copyAsShown": false, "returnCopies": true, "log": false, "welcome": true,
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

struct ConstantsSettings: View {
    @AppStorage("constant.g") private var g = true
    @AppStorage("constant.G") private var bigG = true
    @AppStorage("constant.c") private var c = true
    @AppStorage("precise") private var precise = false

    // What each constant is shown working in.
    private static let examples = [["h=0.5g*3^2", "2g=10"], ["F=G*5*6/2^2"], ["9e16=!c^2"]]

    var body: some View {
        Form {
            Section("Which letters are constants") {
                ForEach(Array(Constants.table.enumerated()), id: \.offset) { index, row in
                    let isOn = [$g, $bigG, $c][index]
                    Toggle(isOn: isOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.name)   \(row.title)")
                            Text(precise ? row.precise.text : row.booklet.text).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .feel(isOn.wrappedValue, showing: Self.examples[min(index, Self.examples.count - 1)])
                }
                note("A letter is its constant only where the equation has another letter to solve for: h = 0.5g·3² uses g, and 2g = 10 is solved for g. A ! before the letter turns that round: 9e16 = !c² is about the speed of light. Switch one off to keep its letter always an unknown.")
            }
            Section("Values") {
                Picker("Values", selection: $precise) {
                    Text("Rounded").tag(false)
                    Text("As measured").tag(true)
                }
                .pickerStyle(.segmented)
                .feel(precise, showing: ["F=G*5*6/2^2"])
                note(precise ? "The values as they are known, to more figures than the booklet gives: use these for a real quantity."
                             : "The values as a data booklet rounds them, to three figures or so, which is what a mark scheme works from.")
            }
        }
        .formStyle(.grouped)
    }
}

struct CopyingSettings: View {
    @AppStorage("copyAsShown") private var copyAsShown = false
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
