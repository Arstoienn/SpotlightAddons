import AppKit
import ServiceManagement
import SwiftUI

// The settings window. It is opened by Spotlight Plus Settings, the app's entry for it in
// Spotlight's list, or by the gear at the foot of the panel. Each setting is
// kept in the defaults under the name the solver reads it by (Options), or the app (Prefs).
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Spotlight Plus Settings"
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

// What the app itself does or leaves alone. The solver's own choices are in Options.
enum Prefs {
    private static func flag(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }

    static var returnCopies: Bool { flag("returnCopies", true) }
    static var log: Bool { flag("log", false) }
    static var welcome: Bool { flag("welcome", true) }

    // The app was com.arstoienn.spotlight-solve before it was Spotlight Plus. What was chosen
    // and remembered under that name is brought over, the once.
    static func bringOver() {
        let before = "com.arstoienn.spotlight-solve", defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != before, defaults.object(forKey: "broughtOver") == nil else { return }
        for (key, value) in defaults.persistentDomain(forName: before) ?? [:] where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
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

struct SettingsView: View {
    var height: CGFloat = 560
    @State private var resetting = false
    // The page last looked at, kept for the next time.
    @AppStorage("settingsPage") private var page = "answers"

    var body: some View {
        TabView(selection: $page) {
            AnswersSettings().tabItem { Label("Answers", systemImage: "equal.square") }.tag("answers")
            CardsSettings().tabItem { Label("Cards", systemImage: "rectangle.stack") }.tag("cards")
            ConstantsSettings().tabItem { Label("Constants", systemImage: "atom") }.tag("constants")
            CopyingSettings().tabItem { Label("Copying", systemImage: "doc.on.doc") }.tag("copying")
            GeneralSettings(resetting: $resetting).tabItem { Label("General", systemImage: "gearshape") }.tag("general")
        }
        .frame(width: 620, height: height)
        .alert("Reset every setting?", isPresented: $resetting) {
            Button("Reset", role: .destructive) { for key in defaultSettings.keys { UserDefaults.standard.removeObject(forKey: key) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The choices on every page go back to what they were when Spotlight Plus was first opened. Nothing else is touched.")
        }
    }
}

// What a setting does, under it, in the words of an example.
private func note(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

// An example typed into Spotlight, and what it gives now, with the settings as they stand: so
// that turning one off is seen to take the card away.
private struct Example: View {
    let typed: String
    @AppStorage("degrees") private var degrees = false
    @AppStorage("figures") private var figures = 6
    @AppStorage("exact") private var exact = true
    @AppStorage("decimalFirst") private var decimalFirst = true
    @AppStorage("arithmetic") private var arithmetic = true
    @AppStorage("numberFacts") private var numberFacts = true
    @AppStorage("paths") private var paths = true
    @AppStorage("conversions") private var conversions = true
    @AppStorage("basePrefix") private var basePrefix = false
    @AppStorage("inequalities") private var inequalities = true
    @AppStorage("algebra") private var algebra = true
    @AppStorage("matrices") private var matrices = true
    @AppStorage("precise") private var precise = false

    var body: some View {
        // Read here so that the view is made again when any of them changes.
        _ = (degrees, figures, exact, decimalFirst, arithmetic, numberFacts, paths, conversions, basePrefix, inequalities, algebra, matrices, precise)
        let answer = Solver.solve(typed)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(typed).font(.system(.callout, design: .monospaced))
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            if let answer {
                Text(answer.exact + (answer.approx.map { "   " + $0 } ?? "")).font(.callout).lineLimit(2)
            } else {
                Text("no card").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
    }
}

// A switch, with what it does and an example.
private struct CardToggle: View {
    let title: String
    @Binding var isOn: Bool
    let detail: String
    var examples: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            note(detail)
            ForEach(examples, id: \.self) { Example(typed: $0) }
        }
        .padding(.vertical, 2)
    }
}

private struct AnswersSettings: View {
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
                note(degrees ? "An angle marked rad, or with π in it, is still in radians: sin(x rad), sin(π/6)."
                             : "An angle marked deg or ° is in degrees: sin(x deg), cos(35°).")
                Example(typed: "sin(x)=0.5")
            }
            Section("Numbers") {
                Picker("Significant figures", selection: $figures) {
                    ForEach(3...10, id: \.self) { Text("\($0)").tag($0) }
                }
                note("How far a decimal is carried. Six is what a calculator shows; three is what an answer is usually asked to.")
                Example(typed: "1/3+0.5*sqrt(2)")

                Toggle("Exact answers where there are any", isOn: $exact)
                note("Fractions, roots and π where they are exact; otherwise decimals only.")
                Example(typed: "2n^2=10")

                Toggle("Decimals before fractions in a sum", isOn: $decimalFirst)
                    .disabled(!exact)
                note(decimalFirst ? "A sum is answered as a decimal first, with the fraction beneath it."
                                  : "A sum is answered as a fraction first, with the decimal beneath it.")
                Example(typed: "10/4")
                Example(typed: "1/3+1/6")
            }
        }
        .formStyle(.grouped)
    }
}

private struct CardsSettings: View {
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
                           examples: ["3 in binary"])
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

private struct ConstantsSettings: View {
    @AppStorage("constant.g") private var g = true
    @AppStorage("constant.G") private var bigG = true
    @AppStorage("constant.c") private var c = true
    @AppStorage("precise") private var precise = false

    var body: some View {
        Form {
            Section("Which letters are constants") {
                ForEach(Array(Constants.table.enumerated()), id: \.offset) { index, row in
                    Toggle(isOn: [$g, $bigG, $c][index]) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.name)   \(row.title)")
                            Text(precise ? row.precise.text : row.booklet.text).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                note("A letter is its constant only where the equation has another letter to solve for: h = 0.5g·3² uses g, and 2g = 10 is solved for g. A ! before the letter turns that round: 9e16 = !c² is about the speed of light. Switch one off to keep its letter always an unknown.")
                Example(typed: "h=0.5g*3^2")
                Example(typed: "2g=10")
            }
            Section("Values") {
                Picker("Values", selection: $precise) {
                    Text("Rounded").tag(false)
                    Text("As measured").tag(true)
                }
                .pickerStyle(.segmented)
                note(precise ? "The values as they are known, to more figures than the booklet gives: use these for a real quantity."
                             : "The values as a data booklet rounds them, to three figures or so, which is what a mark scheme works from.")
                Example(typed: "F=G*5*6/2^2")
            }
        }
        .formStyle(.grouped)
    }
}

private struct CopyingSettings: View {
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
                note("A decimal is what another program can read, and is given to twelve figures whatever is chosen on the Answers page. Several answers are copied with commas between: 2, 3.")
            }
            Section("Return") {
                Toggle("Return copies, while the pointer is on the card", isOn: $returnCopies)
                note("With the pointer anywhere else, Return is Spotlight's and opens what is chosen in its list.")
            }
            Section("Afterwards") {
                note("What is copied becomes ans, for the next sum: ans*2. Where there were several answers they are ans1, ans2 and so on. clip is the number on the clipboard: 20*clip.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettings: View {
    @Binding var resetting: Bool
    @AppStorage("log") private var log = false
    @AppStorage("welcome") private var welcome = true
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?

    var body: some View {
        Form {
            Section("Starting") {
                Toggle("Open at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, wanted in
                        do {
                            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginProblem = nil
                        } catch {
                            loginProblem = error.localizedDescription
                            atLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                note(loginProblem ?? "Without this, Spotlight Plus has to be opened again after the Mac is restarted.")

                Toggle("Show a note when it is opened", isOn: $welcome)
                note("A moment's note at the top of the screen that Spotlight Plus is running, since it has no window. It says so too when the permission it needs has not been given.")
            }
            Section("Troubleshooting") {
                Toggle("Keep a log", isOn: $log)
                note("When the card came and went, and why, in ~/Library/Logs/SpotlightPlus.log: for finding out why a card went missing. It has how many characters were typed and never what they were.")
                Button("Show the log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/SpotlightPlus.log")])
                }
                .disabled(!FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Logs/SpotlightPlus.log"))
            }
            Section("Spotlight Plus \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                HStack {
                    Button("Reset every setting…") { resetting = true }
                    Spacer()
                    Button("Quit Spotlight Plus") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// The gear at the foot of the panel.
struct SettingsButton: View {
    static var open: () -> Void = {}

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "gearshape").font(.system(size: 12, weight: .medium))
            Text("Settings").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .overlay(ClickTarget { SettingsButton.open() })
    }
}
