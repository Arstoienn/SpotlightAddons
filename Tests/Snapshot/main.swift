import Foundation

// What every input of the corpus gives: the card, the copy and the working, one line each, so that
// a change of behaviour shows as a difference from the last snapshot. Run with ./test.sh --snapshot.
// The money rates are those the tests fix, and nothing is asked of the network.
UserDefaults.standard.set(false, forKey: "decimalFirst")
Rates.install(["USD": 1, "TWD": 31.5523, "EUR": 0.86, "JPY": 150.2, "BTC": 0.00001, "ETH": 0.0004, "USDT": 1, "XMR": 0.002, "NEAR": 0.5,
               "XAU": 1 / 4000.0, "XAG": 1 / 50.0], recorded: Date(timeIntervalSince1970: 1791417751), offline: false)

let arguments = CommandLine.arguments
let corpus = (try? String(contentsOfFile: arguments[1], encoding: .utf8)) ?? ""
var lines: [String] = [], times: [(Double, String)] = []
for typed in corpus.split(separator: "\n").map(String.init) {
    let start = Date()
    let solution = Solver.solve(typed)
    let details = Solver.details(typed)
    let copy = Solver.copy(typed)
    let values = Solver.values(typed).map { String(format: "%.12g", $0) }.joined(separator: ", ")
    times.append((Date().timeIntervalSince(start) * 1000, typed))
    var working = ""
    if let d = details {
        let steps = d.steps.map { "\($0.label): \($0.math?.plain ?? $0.note ?? "")" }.joined(separator: " | ")
        working = "\(d.equation.plain) ‖ \(steps) ‖ \(d.solutions.map(\.plain).joined(separator: "; "))" + (d.note.map { " ‖ \($0)" } ?? "")
    }
    let card = solution.map { "\($0.exact) ⁄ \($0.approx ?? "")" } ?? "nil"
    lines.append([typed, card, copy ?? "", working, values].joined(separator: "\t"))
}
try? (lines.joined(separator: "\n") + "\n").write(toFile: arguments[2], atomically: true, encoding: .utf8)
// The slowest inputs, for each keystroke in Spotlight waits on one.
let slow = times.sorted { $0.0 > $1.0 }.prefix(15).map { String(format: "%8.2f ms  %@", $0.0, $0.1) }
print("\(lines.count) inputs; slowest:\n" + slow.joined(separator: "\n"))
