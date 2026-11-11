import Foundation

// Every question in Tests/booklets.json, taken from the IB Mathematics AA HL formula booklet and the
// Physics data booklet, put to the solver, and its answer checked against the one worked out
// independently: ./test.sh --booklets. Each failure is printed with what was typed, what was wanted
// and what came; the last line is the count.
//   value     the answer is this number              roots    the solutions are these numbers
//   function  the result, an expression in x, has these values at these points
//   symbolic  the same, the expected expression given  text     the card's line contains this
//   proof     the card says the equation holds for every value
//   vector    the components are these               complex  the real and imaginary parts are these

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/booklets.json"
guard let data = FileManager.default.contents(atPath: path),
      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { print("No booklet questions at \(path)"); exit(1) }

func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-5 * max(1, abs(a), abs(b)) }

// The numbers written in a line of the card, as the card writes them: −2, 3/2, 1.5×10⁻⁷.
func numbers(_ text: String) -> [Double] {
    var s = text.replacingOccurrences(of: "−", with: "-")
    let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
    if let pattern = try? NSRegularExpression(pattern: "×10([⁻⁰¹²³⁴⁵⁶⁷⁸⁹]+)") {
        for m in pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let r = Range(m.range, in: s), let e = Range(m.range(at: 1), in: s) else { continue }
            s.replaceSubrange(r, with: "e" + String(s[e].map { superscripts[$0] ?? $0 }))
        }
    }
    guard let pattern = try? NSRegularExpression(pattern: "-?[0-9]+(?:\\.[0-9]+)?(?:e-?[0-9]+)?(?:/[0-9]+(?:\\.[0-9]+)?)?") else { return [] }
    return pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
        guard let r = Range(m.range, in: s) else { return nil }
        let parts = s[r].split(separator: "/")
        guard let top = Double(parts[0]) else { return nil }
        return parts.count == 2 ? Double(parts[1]).map { top / $0 } : top
    }
}

// An expression in x, as the card writes it, worked out at a point.
func value(of written: String, at x: Double) -> Double? {
    var text = written.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("= ") { text.removeFirst(2) }
    text = text.replacingOccurrences(of: " + C", with: "")
    // ln|x| as the card writes it: the bars are abs( ).
    text = text.replacingOccurrences(of: "\\|([^|]+)\\|", with: "abs($1)", options: .regularExpression)
    guard let tokens = try? Parser.tokenize(text) else { return nil }
    var state = Parser.State(tokens: tokens, unknown: "x", bound: [])
    guard let e = try? state.expression(), state.at == tokens.count else { return nil }
    let v = e.eval(x)
    return v.isFinite ? v : nil
}

// a + bi, as the card writes it: 5 + 5i, −2i, 1 + 1.73205i.
func complexParts(_ text: String) -> (Double, Double)? {
    var s = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: " ", with: "")
    if s.hasPrefix("=") || s.hasPrefix("≈") { s.removeFirst() }
    guard s.hasSuffix("i") else { return numbers(s).first.map { ($0, 0) } }
    s.removeLast()
    var split = s.index(before: s.endIndex)
    while split > s.startIndex, !"+-".contains(s[split]) || s[s.index(before: split)] == "e" { split = s.index(before: split) }
    let (realText, imaginaryText) = (String(s[..<split]), String(s[split...]))
    let imaginary = imaginaryText == "+" || imaginaryText.isEmpty ? 1 : imaginaryText == "-" ? -1 : numbers(imaginaryText).first ?? .nan
    return (numbers(realText).first ?? 0, imaginary)
}

var passed = 0, failed: [String] = []
for item in items {
    guard let input = item["input"] as? String, let kind = item["kind"] as? String else { continue }
    let reference = item["ref"] as? String ?? ""
    let answer = Solver.answer(input)
    let line = answer.map { "\($0.solution.exact)" + ($0.solution.approx.map { " / " + $0 } ?? "") } ?? "no card"
    let shown = answer?.solution.exact ?? ""
    let found = (answer?.values ?? []) + numbers(shown)
    var ok = false
    switch kind {
    case "value":
        if let want = item["expected"] as? Double { ok = found.contains { close($0, want) } }
    case "roots", "vector":
        if let want = item["expected"] as? [Double] {
            let got = answer?.values.isEmpty == false ? answer!.values : numbers(shown)
            ok = want.allSatisfy { w in got.contains { close($0, w) } } && (kind == "vector" ? got.count == want.count : true)
        }
    case "text":
        if let want = item["expected"] as? String { ok = shown.contains(want) || line.contains(want) }
    case "proof":
        ok = shown.contains("∈ ℝ") || shown == "True"
    case "complex":
        if let want = item["expected"] as? [Double], let (re, im) = complexParts(shown) { ok = close(re, want[0]) && close(im, want[1]) }
    case "function":
        if let want = item["expected"] as? [Double], let points = item["points"] as? [Double], let copied = answer?.copy {
            ok = zip(points, want).allSatisfy { p, w in value(of: copied, at: p).map { close($0, w) } ?? false }
        }
    case "symbolic":
        if let want = item["expected"] as? String, let copied = answer?.copy {
            ok = [0.3, 1.7, -2.4].allSatisfy { p in
                guard let a = value(of: copied, at: p), let b = value(of: want, at: p) else { return false }
                return close(a, b)
            }
        }
    default: break
    }
    if ok { passed += 1 } else { failed.append("FAIL [\(reference)] \(kind)  \(input)\n     want \(item["expected"] ?? "")\n     got  \(line)") }
}
for f in failed { print(f) }
print("\(passed) of \(items.count) booklet questions answered correctly")
