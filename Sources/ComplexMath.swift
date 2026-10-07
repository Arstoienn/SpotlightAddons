import Foundation

// Arithmetic with i: (1+2i)(3−i), i², e^(iπ), |3+4i|, and a root of a negative number inside a
// larger sum. Taken only when i stands by itself in the sum, or a real answer is not to be had.
struct Complex: Equatable {
    var re: Double, im: Double
    init(_ re: Double, _ im: Double = 0) { (self.re, self.im) = (re, im) }

    static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re + 0, a.im - b.im + 0) }
    static func * (a: Complex, b: Complex) -> Complex { Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re) }
    static func / (a: Complex, b: Complex) -> Complex {
        let d = b.re * b.re + b.im * b.im
        return Complex((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d)
    }
    var modulus: Double { hypot(re, im) }
    var argument: Double { atan2(im, re) }
    var isFinite: Bool { re.isFinite && im.isFinite }

    static func exp(_ z: Complex) -> Complex { Complex(Foundation.exp(z.re) * cos(z.im), Foundation.exp(z.re) * sin(z.im)) }
    static func log(_ z: Complex) -> Complex { Complex(Foundation.log(z.modulus), z.argument) }
    static func pow(_ a: Complex, _ b: Complex) -> Complex {
        if a.re == 0, a.im == 0 { return b.re == 0 && b.im == 0 ? Complex(1) : Complex(0) }
        // A whole power is repeated multiplication, which is exact where the polar form is not.
        if b.im == 0, b.re == b.re.rounded(), abs(b.re) <= 64 {
            var r = Complex(1)
            for _ in 0..<Int(abs(b.re)) { r = r * a }
            return b.re < 0 ? Complex(1) / r : r
        }
        return exp(b * log(a))
    }
    static func sqrt(_ z: Complex) -> Complex {
        let m = z.modulus
        let re = ((m + z.re) / 2).squareRoot(), im = ((m - z.re) / 2).squareRoot()
        return Complex(re, z.im < 0 ? -im : im)
    }
}

struct ComplexValue {
    var value: Complex
    var expr: Expr

    // Whether the input is for this: i stands alone in it, and nothing else is a letter.
    static func parse(_ input: String, force: Bool = false) -> ComplexValue? {
        guard Options.arithmetic, !input.contains("="), !input.contains(",") else { return nil }
        guard var tokens = try? Parser.tokenize(input), !tokens.isEmpty else { return nil }
        let hasI = tokens.contains(.letter("i"))
        guard hasI || force else { return nil }
        tokens = tokens.map { $0 == .letter("e") ? .constant(M_E) : $0 }
        guard !tokens.contains(where: { if case .letter(let s) = $0 { s != "i" } else { false } }),
              !tokens.contains(where: { if case .named = $0 { true } else { false } }) || true else { return nil }
        var state = Parser.State(tokens: tokens, unknown: "", bound: hasI ? ["i"] : [])
        guard let expr = try? state.expression(), state.at == tokens.count, !expr.hasUnknown else { return nil }
        // At least a digit or an operator: i alone, or ii, is no sum.
        guard input.contains(where: { $0.isNumber || "+-*/^()".contains($0) }) else { return nil }
        guard let z = evaluate(expr), z.isFinite else { return nil }
        // Nothing complex in it, and a real answer: the ordinary path has it.
        if !hasI, abs(z.im) < 1e-12 { return nil }
        return ComplexValue(value: snapped(z), expr: expr)
    }

    static func snapped(_ z: Complex) -> Complex {
        func s(_ x: Double) -> Double {
            if abs(x) < 1e-12 { return 0 }
            let r = x.rounded()
            return abs(x - r) <= 1e-12 * max(1, abs(x)) ? r : x
        }
        return Complex(s(z.re), s(z.im))
    }

    static func evaluate(_ e: Expr) -> Complex? {
        switch e {
        case .num(let v), .constant(_, let v): return Complex(v)
        case .index(let k): return k == "i" ? Complex(0, 1) : nil
        case .unknown, .sum, .apply: return nil
        case .neg(let a): return evaluate(a).map { Complex(0 - $0.re, 0 - $0.im) }
        case .op(let o, let a, let b):
            guard let x = evaluate(a), let y = evaluate(b) else { return nil }
            switch o {
            case "+": return x + y
            case "-": return x - y
            case "*": return x * y
            case "/": return y.re == 0 && y.im == 0 ? nil : x / y
            case "^": return Complex.pow(x, y)
            default: return nil
            }
        case .call(let f, let a):
            guard let z = evaluate(a) else { return nil }
            switch f {
            case "sqrt": return Complex.sqrt(z)
            case "exp": return Complex.exp(z)
            case "ln": return z.re == 0 && z.im == 0 ? nil : Complex.log(z)
            case "log": return z.re == 0 && z.im == 0 ? nil : Complex.log(z) / Complex(Foundation.log(10))
            case "abs": return Complex(z.modulus)
            case "conj": return Complex(z.re, -z.im)
            case "arg": return Complex(z.argument)
            case "real": return Complex(z.re)
            case "imag": return Complex(z.im)
            case "sin": return Complex(sin(z.re) * cosh(z.im), cos(z.re) * sinh(z.im))
            case "cos": return Complex(cos(z.re) * cosh(z.im), -sin(z.re) * sinh(z.im))
            case "sinh": return Complex(sinh(z.re) * cos(z.im), cosh(z.re) * sin(z.im))
            case "cosh": return Complex(cosh(z.re) * cos(z.im), sinh(z.re) * sin(z.im))
            case "tan":
                guard let s = evaluate(.call("sin", a)), let c = evaluate(.call("cos", a)) else { return nil }
                return s / c
            case "deg": return Complex(z.re * .pi / 180, z.im * .pi / 180)
            case "rad": return z
            default: return nil
            }
        }
    }

    private static func part(_ x: Double) -> String {
        if abs(x) < 1e-12 { return "0" }
        if Options.exact, abs(x) < 1e7, let (p, q) = rational(x), q <= 1000, abs(Double(p) / Double(q) - x) <= 1e-12 * max(1, abs(x)) {
            return fraction(p, q)
        }
        return decimal(x)
    }

    // a + bi, with 1 and nothing before an i left out.
    var text: String {
        let z = value
        let (r, i) = (Self.part(z.re), Self.part(z.im))
        if z.im == 0 { return r }
        let magnitude = i.hasPrefix("−") ? String(i.dropFirst()) : i
        var imaginary = (magnitude == "1" ? "" : magnitude) + "i"
        // 5/2 i is written 5i/2.
        if let slash = magnitude.firstIndex(of: "/") {
            let top = String(magnitude[..<slash]), bottom = String(magnitude[magnitude.index(after: slash)...])
            imaginary = (top == "1" ? "i" : "\(top)i") + "/" + bottom
        }
        if z.re == 0 { return (i.hasPrefix("−") ? "−" : "") + imaginary }
        return "\(r) \(i.hasPrefix("−") ? "−" : "+") \(imaginary)"
    }

    var solution: Solution {
        let z = value
        if z.im == 0 { return Solution(exact: "= " + text, approx: nil) }
        let polar = "|z| = \(decimal(z.modulus)), arg = \(decimal(z.argument)) rad"
        return Solution(exact: "= " + text, approx: polar)
    }

    var details: Details {
        var d = Details(name: "", equation: typeset(expr, ""), steps: [], solutions: [t("= " + text)], note: nil, f: { _ in .nan }, roots: [])
        d.steps.append(Step(label: "Evaluating with i² = −1", math: t("= " + text)))
        if value.im != 0 {
            d.steps.append(Step(label: "Writing in polar form", math: t("|z| = \(decimal(value.modulus)), arg z = \(decimal(value.argument)) rad"),
                                note: "The modulus is the distance from the origin, and the argument the angle from the positive real axis."))
            d.solutions.append(t("|z| = \(decimal(value.modulus)), arg = \(decimal(value.argument)) rad"))
        }
        return d
    }

    // A real result as a number to full precision; a complex one as a + bi, its parts to twelve figures.
    var copyText: String {
        func figure(_ x: Double) -> String { String(format: "%.12g", x) }
        if value.im == 0 { return figure(value.re) }
        if value.re == 0 { return figure(value.im) + "i" }
        return figure(value.re) + (value.im < 0 ? "-" : "+") + figure(abs(value.im)) + "i"
    }
    var values: [Double] { value.im == 0 ? [value.re] : [] }
}
