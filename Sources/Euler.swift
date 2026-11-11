import Foundation

// Euler's method for dy/dx = f(x, y), as the formula booklet gives it: y_{n+1} = y_n + h·f(x_n, y_n),
// x_{n+1} = x_n + h. Typed euler(f, x₀, y₀, h, n): euler(x+y, 0, 1, 0.1, 3) takes three steps of 0.1
// from y(0) = 1, and gives y(0.3) = 1.362. Each step is written out with its numbers.
struct Euler {
    var slope: Expr                 // f(x, y), x and y each a letter of its own
    var slopeText: Math
    var x0: Double, y0: Double, h: Double, steps: Int
    var points: [(x: Double, y: Double, f: Double)]   // each point reached, and the slope there

    static func parse(_ input: String) -> Euler? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.lowercased().hasPrefix("euler("), text.hasSuffix(")") else { return nil }
        let arguments = Taylor.topLevel(String(text.dropFirst(6).dropLast())).map { $0.trimmingCharacters(in: .whitespaces) }
        guard arguments.count == 5, let tokens = try? Parser.tokenize(arguments[0]) else { return nil }
        var state = Parser.State(tokens: tokens, unknown: "", bound: ["x", "y"])
        guard let slope = try? state.expression(), state.at == tokens.count,
              let x0 = (try? Parser.constant(arguments[1]))?.eval(0), let y0 = (try? Parser.constant(arguments[2]))?.eval(0),
              let h = (try? Parser.constant(arguments[3]))?.eval(0), let n = (try? Parser.constant(arguments[4]))?.eval(0),
              x0.isFinite, y0.isFinite, h.isFinite, h != 0, n == n.rounded(), n >= 1, n <= 10_000 else { return nil }
        var points: [(x: Double, y: Double, f: Double)] = []
        var (x, y) = (x0, y0)
        for _ in 0..<Int(n) {
            let f = slope.eval(0, ["x": x, "y": y])
            guard f.isFinite else { return nil }
            points.append((x, y, f))
            (x, y) = (x + h, y + h * f)
        }
        points.append((x, y, .nan))
        return Euler(slope: slope, slopeText: typeset(slope, ""), x0: x0, y0: y0, h: h, steps: Int(n), points: points)
    }

    private var last: (x: Double, y: Double) { (points.last!.x, points.last!.y) }

    // = where the decimal shown is the whole of the value, 1.362, or differs from it only by the
    // computer's rounding, 1.22 for 1.2200000000000002; ≈ where it is cut short.
    private static func equals(_ v: Double) -> String { shownWhole(v) ? "= \(decimal(v))" : "≈ \(decimal(v))" }

    var solution: Solution {
        Solution(exact: "y(\(decimal(last.x))) \(Euler.equals(last.y))",
                 approx: "By Euler's method, in \(steps) step\(steps == 1 ? "" : "s") of h = \(decimal(h))")
    }

    var values: [Double] { [last.y] }

    var details: Details {
        let heading = row(t("dy/dx = "), slopeText, t(",  x₀ = \(decimal(x0)),  y₀ = \(decimal(y0)),  h = \(decimal(h))"))
        var d = Details(name: "", equation: heading, steps: [], solutions: [t(solution.exact)], note: nil, f: { _ in .nan }, roots: [])
        d.steps.append(Step(label: "Applying Euler's method", math: t("yₙ₊₁ = yₙ + h·f(xₙ, yₙ),  xₙ₊₁ = xₙ + h")))
        func number(_ v: Double) -> String { v < 0 ? "(\(decimal(v)))" : decimal(v) }
        // Each step, up to twenty; a longer run is finished in one.
        for (k, p) in points.dropLast().enumerated().prefix(20) {
            let next = points[k + 1]
            d.steps.append(Step(label: "Taking step \(k + 1)",
                                math: t("y\(Euler.subscripted(k + 1)) = \(decimal(p.y)) + \(decimal(h)) × f(\(decimal(p.x)), \(decimal(p.y))) = \(decimal(p.y)) + \(decimal(h)) × \(number(p.f)) \(Euler.equals(next.y))")))
        }
        if steps > 20 { d.steps.append(Step(label: "Taking the remaining steps", math: nil, note: "The other \(steps - 20) steps are taken in the same way.")) }
        d.graph = nil
        return d
    }

    private static func subscripted(_ n: Int) -> String {
        let digits: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(String(n).map { digits[$0] ?? $0 })
    }
}

// Whether the decimal shown for v is the whole of it, but for the computer's rounding: 1.22 is the
// whole of 1.2200000000000002, and 0.829156 is not the whole of √0.6875.
func shownWhole(_ v: Double) -> Bool {
    guard let shown = Double(decimal(v).replacingOccurrences(of: "−", with: "-")) else { return false }
    return abs(shown - v) <= 1e-12 * max(1, abs(v))
}
