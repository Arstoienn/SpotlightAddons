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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
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

struct SettingsView: View {
    var height: CGFloat = 720   // of the window; what is in it is longer, and scrolls
    @AppStorage("degrees") private var degrees = false
    @AppStorage("figures") private var figures = 6
    @AppStorage("exact") private var exact = true
    @AppStorage("arithmetic") private var arithmetic = true
    @AppStorage("numberFacts") private var numberFacts = true
    @AppStorage("paths") private var paths = true
    @AppStorage("conversions") private var conversions = true
    @AppStorage("basePrefix") private var basePrefix = false
    @AppStorage("inequalities") private var inequalities = true
    @AppStorage("algebra") private var algebra = true
    @AppStorage("matrices") private var matrices = true
    @AppStorage("constant.g") private var g = true
    @AppStorage("constant.G") private var bigG = true
    @AppStorage("constant.c") private var c = true
    @AppStorage("precise") private var precise = false
    @AppStorage("copyAsShown") private var copyAsShown = false
    @AppStorage("returnCopies") private var returnCopies = true
    @AppStorage("log") private var log = false
    @AppStorage("welcome") private var welcome = true
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    @State private var loginProblem: String?

    var body: some View {
        Form {
            Section("Answers") {
                Picker("Angles are in", selection: $degrees) {
                    Text("Radians").tag(false)
                    Text("Degrees").tag(true)
                }
                note(degrees ? "sin(x) = 0.5 gives x = 30°, 150°. An angle marked rad, or with π in it, is still in radians: sin(x rad), sin(π/6)."
                             : "sin(x) = 0.5 gives x = π/6, 5π/6. An angle marked deg or ° is in degrees: sin(x deg), cos(35°).")

                Picker("Significant figures", selection: $figures) {
                    ForEach(3...10, id: \.self) { Text("\($0)").tag($0) }
                }
                note("How far a decimal is carried: 1/3 is \(third). Six is what a calculator shows; three is what an answer is usually asked to.")

                Toggle("Exact answers where there are any", isOn: $exact)
                note(exact ? "10/4 gives 5/2, with 2.5 beneath; 2n² = 10 gives n = ±√5; an angle gives π/6."
                           : "Decimals only: 10/4 gives 2.5, and 2n² = 10 gives n ≈ ±2.23607.")
            }

            Section("What brings up a card") {
                Toggle("Arithmetic with no equals sign", isOn: $arithmetic)
                note("12*3+4, 5!/(3!2!), sqrt(2). Turn this off if Spotlight's own calculator is on, or the two will both answer. A name still works: x = 12*3+4.")

                Toggle("A number typed by itself", isOn: $numberFacts)
                note("2048 gives 2¹¹, 97 is prime, 0.375 gives 3/8. Turned on, every number typed into Spotlight brings up a card, a year among them.")

                Toggle("Units and number bases", isOn: $conversions)
                note("5 km to miles, 100 F in C, 255 in hex, hex(255). Only a quantity and a unit known to the calculator, and a unit of the same kind to convert to.")

                Toggle("Mark a base with its prefix", isOn: $basePrefix)
                note("255 in hex is FF; with this on it is 0xFF, and 3 in binary is 0b11, not 11. The prefix is always understood when typed: 0xFF + 1 is 256.")

                Toggle("Inequalities", isOn: $inequalities)
                note("x^2>4 gives x < −2 or x > 2. Polynomials in one letter.")

                Toggle("Algebra by name", isOn: $algebra)
                note("expand((x+1)^2), factor(x^2-5x+6), derivative(x^3), integrate(x^2, 0, 1) and d/dx sin(x). Nothing is done to an expression unless it is asked for.")

                Toggle("Matrices and vectors", isOn: $matrices)
                note("det([[1,2],[3,4]]), inv, transpose, dot([1,2,3],[4,5,6]), cross, and products and sums of them.")

                Toggle("A path to a file or folder", isOn: $paths)
                note("/Users/shane/Code/App/app.jar names the file, and shows it in Finder when the card is clicked, or Return is pressed with the pointer on it. A folder is opened. Only a path that exists brings up a card.")
            }

            Section("Physical constants") {
                ForEach(Array(Constants.table.enumerated()), id: \.offset) { index, row in
                    Toggle(isOn: [$g, $bigG, $c][index]) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.name)   \(row.title)")
                            Text(precise ? row.precise.text : row.booklet.text).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Values", selection: $precise) {
                    Text("Rounded").tag(false)
                    Text("As measured").tag(true)
                }
                note(precise ? "The values as they are known, to more figures than the booklet gives: use these for a real quantity."
                             : "The values as a data booklet rounds them, to three figures or so, which is what a mark scheme works from.")
                note("A letter is its constant only where the equation has another letter to solve for: h = 0.5g·3² uses g, and 2g = 10 is solved for g. A ! before the letter turns that round: 9e16 = !c² is about the speed of light. Switch one off to keep its letter always an unknown, c for a specific heat capacity, say.")
            }

            Section("Copying") {
                Picker("The copy button copies", selection: $copyAsShown) {
                    Text("A decimal: 2.5").tag(false)
                    Text("The answer as shown: 5/2").tag(true)
                }
                note("A decimal is what another program can read, and is given to twelve figures whatever is chosen above. Several answers are copied with commas between: 2, 3.")

                Toggle("Return copies, while the pointer is on the card", isOn: $returnCopies)
                note("With the pointer anywhere else, Return is Spotlight's and opens what is chosen in its list. What is copied becomes ans, for the next sum: ans*2. Where there were several answers they are ans1, ans2 and so on.")
            }

            Section("General") {
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

                Toggle("Keep a log", isOn: $log)
                note("When the card came and went, and why, in ~/Library/Logs/SpotlightPlus.log: for finding out why a card went missing. It has how many characters were typed and never what they were.")

                HStack {
                    Text("Spotlight Plus \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Spotlight Plus") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: height)
    }

    // 1/3 to as many figures as are chosen.
    private var third: String { String(format: "%.\(figures)f", 1.0 / 3) }

    // What a setting does, under it, in the words of an example.
    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
