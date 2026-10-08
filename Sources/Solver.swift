import Foundation

// Solves one equation in one unknown, typed the way you would into a calculator: "2n^2=10",
// "x^3-2x=1", "sin(x)=0.5", "2^x=10". Polynomials up to degree two are solved exactly
// ("n = ±√5"); everything else is solved numerically for its real roots.

struct Solution: Equatable {
    var exact: String          // "n = ±√5", or the decimal answer when there is no exact one
    var approx: String?        // "≈ ±2.23607", when it says something the exact line does not
}

enum Solver {
    static func solve(_ typed: String) -> Solution? {
        if let place = Location.parse(typed) { return place.solution }
        // Money is read as typed: a $ before the amount is no mark of mathematics.
        if let money = Currency.conversion(typed) { return money.solution }
        // A digest is of the text exactly as typed. One asked for as a number, inside a sum, is
        // written in as that number first; one in hexadecimal inside a sum is nothing to work out.
        if let hash = Hash.parse(typed) { return hash.solution }
        guard let typed = Hash.numbers(in: typed).map(Prose.tidy), !Prose.reads(typed) else { return nil }
        // "x=?" after a formula asks for it to be turned round to give x.
        // u_1 = 12, u_5 = 29, u_10 = ? asks for the tenth term, and is no "x = ?" after a formula.
        if let sequence = Sequence.parse(Latex.plain(typed)) { return sequence.solution }
        let asked = Rearrangement.asked(Latex.plain(typed))
        let input = asked?.equation ?? Latex.plain(typed)
        // ans, when the question before had several answers, is no one of them: the card says
        // what to write instead.
        if Memory.answers.count > 1, input.range(of: "(?<![A-Za-z])[Aa]ns(?![A-Za-z0-9_])", options: .regularExpression) != nil {
            let named = Memory.answers.prefix(4).enumerated().map { "ans\($0 + 1) = \(decimal($1))" }.joined(separator: ", ")
            return Solution(exact: "ans has \(Memory.answers.count) values", approx: "Write \(named)\(Memory.answers.count > 4 ? ", …" : "").")
        }
        if let matrix = MatrixValue.parse(input) { return matrix.solution }
        if let algebra = Algebra.parse(input) { return algebra.solution }
        if let domain = Domain.parse(input) { return domain.solution }
        if LinearSystem.parts(input).count >= 2 {
            return Given.parse(input)?.solution ?? LinearSystem.parse(input)?.solution ?? NonlinearSystem.parse(input)?.solution
        }
        if let conversion = Conversion.parse(input) { return conversion.solution }
        if let complex = ComplexValue.parse(input) { return complex.solution }
        if Options.numberFacts, let number = NumberFacts.parse(input) { return number.solution }
        if let logic = Logic.parse(input) { return logic.solution }
        if let comparison = Comparison.parse(input) { return comparison.solution }
        if let inequality = Inequality.parse(input) { return inequality.solution }
        if let inequalities = InequalitySet.parse(input) { return inequalities.solution }
        if let evaluation = Evaluation.parse(input, hadLatex: typed.contains("\\")) { return evaluation.solution }
        // cost = 90 gives a name a number, and there is nothing to work out: it is not cos t = 90.
        if Evaluation.namesNumber(input) { return nil }
        if let simplification = Simplification.parse(input) { return simplification.solution }
        if let trig = TrigSimplification.parse(input) { return trig.solution }
        guard let equation = try? Parser.parse(input) else { return Rearrangement.parse(input, for: asked?.letter)?.solution }
        // "x = 5" is already its own answer. "x_1 = 10" and "theta = 30" are not quite: the card
        // has the name as it is written, x with its subscript and θ.
        let name = equation.unknown
        let asTyped = name.count == 1 && name.first?.isASCII == true
        if asTyped, case .unknown = equation.left, case .num = equation.right { return nil }
        if asTyped, case .num = equation.left, case .unknown = equation.right { return nil }
        // With a physical constant in it the answer is a decimal, the constant being only a few
        // figures itself, and the card says what was taken for it when it has the room.
        let constants = equation.constants
        var solution: Solution?
        if let left = poly(equation.left), let right = poly(equation.right) {
            solution = solvePolynomial(trim(sub(left, right)), name, exact: constants.isEmpty && Options.exact)
        } else if let rational = RationalEquation.parse(equation), let found = rational.solution {
            solution = found
        } else {
            solution = solveNumerically(equation, name)
        }
        if !constants.isEmpty, solution?.approx == nil { solution?.approx = "Taking " + Constants.values(constants) }
        return solution
    }
}

// MARK: - Expressions

indirect enum Expr {
    case num(Double)
    case unknown
    case neg(Expr)
    case op(Character, Expr, Expr)   // + - * / ^
    case call(String, Expr)
    case index(String)                                       // the k of a sum, not the unknown
    case constant(String, Double)                            // g, read as 9.8
    case sum(String, from: Expr, to: Expr, Expr, product: Bool)
    case apply(String, [Expr])                               // a function of several numbers: mean(2, 4, 9)

    // indices: the value of each sum's k while its terms are being worked out.
    func eval(_ x: Double, _ indices: [String: Double] = [:]) -> Double {
        switch self {
        case .num(let v), .constant(_, let v): return v
        case .unknown: return x
        case .index(let k): return indices[k] ?? .nan
        case .neg(let e): return -e.eval(x, indices)
        case .op(let o, let a, let b):
            let l = a.eval(x, indices), r = b.eval(x, indices)
            switch o {
            case "+": return added(l, r)
            case "-": return added(l, -r)
            case "*": return l * r
            case "/": return l / r
            default: return Binary.table[o]?.apply(l, r) ?? pow(l, r)
            }
        case .call(let f, let e): return Functions.apply(f, e.eval(x, indices))
        case .apply(let f, let args): return Lists.apply(f, args.map { $0.eval(x, indices) })
        case .sum(let k, let from, let to, let body, let product):
            guard let range = Expr.range(from.eval(x, indices), to.eval(x, indices)) else { return .nan }
            var total: Double = product ? 1 : 0
            var inner = indices
            for i in range {
                inner[k] = Double(i)
                let v = body.eval(x, inner)
                total = product ? total * v : total + v
            }
            return total
        }
    }

    // The whole numbers a sum runs over: empty when it runs backwards, nil when it cannot run
    // (not whole numbers, or too many terms to add up while typing).
    static func range(_ a: Double, _ b: Double) -> ClosedRange<Int>? {
        guard a.isFinite, b.isFinite, a == a.rounded(), b == b.rounded(), b - a <= 100_000 else { return nil }
        return b < a ? 1...0 : Int(a)...Int(b)
    }

    // This expression with a sum's k replaced by a number: one of its terms.
    func setting(_ k: String, to v: Double) -> Expr {
        switch self {
        case .index(let name): return name == k ? .num(v) : self
        case .num, .unknown, .constant: return self
        case .neg(let a): return .neg(a.setting(k, to: v))
        case .op(let o, let a, let b): return .op(o, a.setting(k, to: v), b.setting(k, to: v))
        case .call(let f, let a): return .call(f, a.setting(k, to: v))
        case .apply(let f, let args): return .apply(f, args.map { $0.setting(k, to: v) })
        case .sum(let name, let from, let to, let body, let product):
            return .sum(name, from: from.setting(k, to: v), to: to.setting(k, to: v),
                        name == k ? body : body.setting(k, to: v), product: product)
        }
    }

    // A number in it that is not a number: what came of dividing by nought, or of a root of −4.
    var hasNonFinite: Bool {
        switch self {
        case .num(let v), .constant(_, let v): return !v.isFinite
        case .unknown, .index: return false
        case .neg(let a), .call(_, let a): return a.hasNonFinite
        case .op(_, let a, let b): return a.hasNonFinite || b.hasNonFinite
        case .apply(_, let args): return args.contains { $0.hasNonFinite }
        case .sum(_, let from, let to, let body, _): return from.hasNonFinite || to.hasNonFinite || body.hasNonFinite
        }
    }

    // Why it has no value, where that is a division by nought, or the logarithm of nought.
    var undefinedReason: String? {
        switch self {
        case .num, .constant, .unknown, .index: return nil
        case .neg(let a): return a.undefinedReason
        case .call(let f, let a):
            if f == "log" || f == "ln", a.eval(0) == 0 { return "The logarithm of zero is not defined." }
            return a.undefinedReason
        case .op(let o, let a, let b):
            if o == "/", b.eval(0) == 0 { return "It is divided by zero." }
            if o == "^", a.eval(0) == 0, b.eval(0) < 0 { return "Zero has no power below zero." }
            return a.undefinedReason ?? b.undefinedReason
        case .apply(let f, let args):
            if let why = args.lazy.compactMap(\.undefinedReason).first { return why }
            guard eval(0).isNaN else { return nil }
            switch f {
            case "mode": return "No value occurs more than once."
            case "invnorm": return "A probability is between 0 and 1, neither included."
            case "binompdf", "binomcdf": return "The trials and the successes are whole numbers, and the chance between 0 and 1."
            default: return nil
            }
        case .sum(_, let from, let to, let body, _): return from.undefinedReason ?? to.undefinedReason ?? body.undefinedReason
        }
    }

    var hasUnknown: Bool {
        switch self {
        case .unknown: return true
        case .num, .index, .constant: return false
        case .neg(let a), .call(_, let a): return a.hasUnknown
        case .op(_, let a, let b): return a.hasUnknown || b.hasUnknown
        case .apply(_, let args): return args.contains { $0.hasUnknown }
        case .sum(_, let from, let to, let body, _): return from.hasUnknown || to.hasUnknown || body.hasUnknown
        }
    }

    var hasSum: Bool {
        switch self {
        case .sum: return true
        case .num, .unknown, .index, .constant: return false
        case .neg(let a), .call(_, let a): return a.hasSum
        case .op(_, let a, let b): return a.hasSum || b.hasSum
        case .apply(_, let args): return args.contains { $0.hasSum }
        }
    }

    // The physical constants in it, each once, in the order they are met.
    var constants: [String] {
        switch self {
        case .constant(let name, _): return [name]
        case .num, .unknown, .index: return []
        case .neg(let a), .call(_, let a): return a.constants
        case .op(_, let a, let b): return unique(a.constants + b.constants)
        case .apply(_, let args): return unique(args.flatMap(\.constants))
        case .sum(_, let from, let to, let body, _): return unique(from.constants + to.constants + body.constants)
        }
    }

    // The same expression with each constant's value written in.
    var withValues: Expr {
        switch self {
        case .constant(_, let v): return .num(v)
        case .num, .unknown, .index: return self
        case .neg(let a): return .neg(a.withValues)
        case .op(let o, let a, let b): return .op(o, a.withValues, b.withValues)
        case .call(let f, let a): return .call(f, a.withValues)
        case .apply(let f, let args): return .apply(f, args.map(\.withValues))
        case .sum(let k, let from, let to, let body, let product):
            return .sum(k, from: from.withValues, to: to.withValues, body.withValues, product: product)
        }
    }
}

func unique(_ names: [String]) -> [String] {
    names.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
}

// a + b, where a result that is only rounding noise beside what was added is zero: 0.1 + 0.2 − 0.3
// is 0. Measured against the numbers themselves, so that one as small as the charge on an electron
// is not taken for noise.
func added(_ a: Double, _ b: Double) -> Double {
    let sum = a + b
    return snapsToZero && sum.isFinite && abs(sum) <= 1e-12 * max(abs(a), abs(b)) ? 0 : sum
}

// Off while a limit is sampled, where 1 − cos x is as small as it is, and not noise.
nonisolated(unsafe) var snapsToZero = true

// The functions of two numbers, each written between its two bracketed arguments: gcd(12, 18) is
// (12)⊓(18) once tidied. The remainder, %, is the one that is written as it is typed.
enum Binary {
    static let table: [Character: (name: String, apply: (Double, Double) -> Double)] = [
        "%": ("mod", { r, m in m == 0 ? .nan : r - m * (r / m).rounded(.down) }),
        "⊓": ("gcd", { a, b in whole(a, b).map { Double(gcd($0, $1)) } ?? .nan }),
        "⊔": ("lcm", { a, b in whole(a, b).map { $0 == 0 || $1 == 0 ? 0 : Double(abs($0 / gcd($0, $1) * $1)) } ?? .nan }),
        "⒞": ("C", { n, k in
            guard let (n, k) = whole(n, k), k >= 0, n >= k, n <= 1000 else { return .nan }
            return (0..<min(k, n - k)).reduce(1.0) { $0 * Double(n - $1) / Double($1 + 1) }.rounded()
        }),
        "⒫": ("P", { n, k in
            guard let (n, k) = whole(n, k), k >= 0, n >= k, n <= 1000 else { return .nan }
            return (0..<k).reduce(1.0) { $0 * Double(n - $1) }
        }),
        "⇇": ("shl", { a, b in bits(a, b).map { $1 < 0 || $1 > 62 ? .nan : Double($0 << $1) } ?? .nan }),
        "⇉": ("shr", { a, b in bits(a, b).map { $1 < 0 || $1 > 62 ? .nan : Double($0 >> $1) } ?? .nan }),
        "⋀": ("and", { a, b in bits(a, b).map { Double($0 & $1) } ?? .nan }),
        "⋁": ("or", { a, b in bits(a, b).map { Double($0 | $1) } ?? .nan }),
        "⊻": ("xor", { a, b in bits(a, b).map { Double($0 ^ $1) } ?? .nan }),
        "⒜": ("atan2", { atan2($0, $1) }),
        "↓": ("min", { min($0, $1) }),
        "↑": ("max", { max($0, $1) }),
        "⌖": ("round", { x, places in
            // Rounded as it is written, 79.695 to 79.70, and not as the computer holds it, a little
            // under that.
            guard places == places.rounded(), abs(places) <= 15, x.isFinite,
                  var written = Decimal(string: String(format: "%.15g", x)) else { return .nan }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &written, Int(places), .plain)
            return NSDecimalNumber(decimal: rounded).doubleValue
        }),
        "⒧": ("log", { x, base in
            let v = log(x) / log(base)
            return pow(base, v.rounded()) == x ? v.rounded() : v
        }),
    ]

    private static func whole(_ a: Double, _ b: Double) -> (Int, Int)? {
        guard a.isFinite, b.isFinite, a == a.rounded(), b == b.rounded(), abs(a) < 1e15, abs(b) < 1e15 else { return nil }
        return (Int(a), Int(b))
    }

    // Two whole numbers small enough to be bits.
    private static func bits(_ a: Double, _ b: Double) -> (Int, Int)? {
        guard a.isFinite, b.isFinite, a == a.rounded(), b == b.rounded(), abs(a) < 9e15, abs(b) < 9e15 else { return nil }
        return (Int(a), Int(b))
    }
}

// Functions of any number of numbers: the mean of a list, the chance of a number of successes.
enum Lists {
    static let names = ["mean", "average", "avg", "median", "mode", "stdevp", "stdev", "variance", "varp", "var", "geomean", "rms", "range",
                        "total", "binompdf", "binomcdf", "normpdf", "normcdf", "normalcdf", "invnorm", "poissonpdf", "poissoncdf",
                        "hypot", "root", "zscore"]

    // How many arguments each takes: nil for any number from one.
    static func accepts(_ f: String, _ n: Int) -> Bool {
        switch f {
        case "binompdf", "binomcdf": return n == 3
        case "poissonpdf", "poissoncdf", "root": return n == 2
        case "zscore": return n == 3
        case "normpdf", "normcdf", "invnorm": return n == 1 || n == 3
        case "normalcdf": return n == 2 || n == 4
        default: return n >= 1
        }
    }

    static func apply(_ f: String, _ v: [Double]) -> Double {
        let n = Double(v.count)
        let mean = v.reduce(0, +) / n
        func variance(_ divisor: Double) -> Double {
            guard divisor > 0 else { return .nan }
            return v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / divisor
        }
        switch f {
        case "mean", "average", "avg": return mean
        case "total": return v.reduce(0, +)
        case "median":
            let s = v.sorted()
            return v.count % 2 == 1 ? s[v.count / 2] : (s[v.count / 2 - 1] + s[v.count / 2]) / 2
        case "mode":
            let counts = Dictionary(grouping: v, by: { $0 }).mapValues(\.count)
            let best = counts.values.max() ?? 0
            return best < 2 ? .nan : counts.filter { $0.value == best }.keys.min() ?? .nan
        case "stdev": return variance(n - 1).squareRoot()
        case "stdevp": return variance(n).squareRoot()
        case "variance", "var": return variance(n - 1)
        case "varp": return variance(n)
        case "geomean": return v.contains { $0 <= 0 } ? .nan : exp(v.reduce(0) { $0 + log($1) } / n)
        case "rms": return (v.reduce(0) { $0 + $1 * $1 } / n).squareRoot()
        case "range": return (v.max() ?? .nan) - (v.min() ?? .nan)
        case "hypot": return v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        case "zscore": return v[2] > 0 ? (v[0] - v[1]) / v[2] : .nan
        case "root":
            let (x, k) = (v[0], v[1])
            guard k != 0 else { return .nan }
            if x < 0, k == k.rounded(), Int(k) % 2 != 0 { return -pow(-x, 1 / k) }
            let r = pow(x, 1 / k)
            if k == k.rounded(), abs(k) < 1e6, pow(r.rounded(), k) == x { return r.rounded() }
            return r
        case "binompdf":
            guard let (k, trials) = whole(v[2], v[0]), v[1] >= 0, v[1] <= 1, k >= 0, k <= trials else { return .nan }
            return binomial(trials, k, v[1])
        case "binomcdf":
            guard let (k, trials) = whole(v[2], v[0]), v[1] >= 0, v[1] <= 1, trials >= 0 else { return .nan }
            return k < 0 ? 0 : (0...min(k, trials)).reduce(0.0) { $0 + binomial(trials, $1, v[1]) }
        case "poissonpdf":
            guard let (k, _) = whole(v[1], 0), v[0] >= 0, k >= 0 else { return .nan }
            return exp(-v[0] + Double(k) * log(v[0]) - lgamma(Double(k) + 1))
        case "poissoncdf":
            guard let (k, _) = whole(v[1], 0), v[0] >= 0 else { return .nan }
            return k < 0 ? 0 : (0...k).reduce(0.0) { $0 + exp(-v[0] + Double($1) * log(v[0]) - lgamma(Double($1) + 1)) }
        case "normpdf":
            let (mu, sigma) = v.count == 3 ? (v[1], v[2]) : (0, 1)
            guard sigma > 0 else { return .nan }
            return exp(-0.5 * pow((v[0] - mu) / sigma, 2)) / (sigma * (2 * Double.pi).squareRoot())
        case "normcdf":
            let (mu, sigma) = v.count == 3 ? (v[1], v[2]) : (0, 1)
            return sigma > 0 ? cdf((v[0] - mu) / sigma) : .nan
        case "normalcdf":
            let (mu, sigma) = v.count == 4 ? (v[2], v[3]) : (0, 1)
            return sigma > 0 ? cdf((v[1] - mu) / sigma) - cdf((v[0] - mu) / sigma) : .nan
        case "invnorm":
            let (mu, sigma) = v.count == 3 ? (v[1], v[2]) : (0, 1)
            return sigma > 0 && v[0] > 0 && v[0] < 1 ? mu + sigma * quantile(v[0]) : .nan
        default: return .nan
        }
    }

    private static func whole(_ a: Double, _ b: Double) -> (Int, Int)? {
        guard a.isFinite, b.isFinite, a == a.rounded(), b == b.rounded(), abs(a) < 1e9, abs(b) < 1e9 else { return nil }
        return (Int(a), Int(b))
    }

    private static func binomial(_ n: Int, _ k: Int, _ p: Double) -> Double {
        if p == 0 { return k == 0 ? 1 : 0 }
        if p == 1 { return k == n ? 1 : 0 }
        return exp(lgamma(Double(n) + 1) - lgamma(Double(k) + 1) - lgamma(Double(n - k) + 1) + Double(k) * log(p) + Double(n - k) * log(1 - p))
    }

    // The standard normal curve's area to the left of z.
    static func cdf(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }

    // The z with that area to its left, by Acklam's rational approximation, then two steps of
    // Newton's method on the area to take it to full precision.
    static func quantile(_ p: Double) -> Double {
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        var x: Double
        if p < 0.02425 {
            let q = (-2 * log(p)).squareRoot()
            x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if p <= 1 - 0.02425 {
            let q = p - 0.5, r = q * q
            x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = (-2 * log(1 - p)).squareRoot()
            x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        for _ in 0..<2 {
            let e = cdf(x) - p, u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
            x -= u / (1 + x * u / 2)
        }
        return x
    }
}

enum Functions {
    static let names = ["sqrt", "asin", "acos", "atan", "sin", "cos", "tan", "exp", "abs", "log", "ln",
                        "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "cbrt", "floor", "ceil", "round", "trunc", "sign",
                        "frac", "fib", "totient", "nextprime", "lg", "lb", "conj", "arg", "real", "imag", "sec", "csc", "cot"] + Lists.names

    static func apply(_ f: String, _ v: Double) -> Double {
        // sin° takes degrees and asin° gives them.
        if f.hasSuffix("°") {
            let name = String(f.dropLast())
            return Angle.functions.contains(name) ? apply(name, v * .pi / 180) : apply(name, v) * 180 / .pi
        }
        switch f {
        case "sqrt": return v.squareRoot()
        case "sin": return crossing(sin(v), v)
        case "cos": return crossing(cos(v), v)
        case "tan": return crossing(tan(v), v)
        case "asin": return asin(v)
        case "acos": return acos(v)
        case "atan": return atan(v)
        case "exp": return exp(v)
        case "abs": return abs(v)
        case "asinh": return asinh(v)
        case "acosh": return acosh(v)
        case "atanh": return atanh(v)
        case "frac": return v - v.rounded(.towardZero)
        case "sec": return 1 / apply("cos", v)
        case "csc": return 1 / apply("sin", v)
        case "cot": return 1 / apply("tan", v)
        case "conj", "real": return v
        case "arg": return v >= 0 ? 0 : .pi
        case "imag": return 0
        case "lg": return log10(v)
        case "lb": return log2(v)
        case "fib": return fibonacci(v)
        case "totient": return totient(v)
        case "nextprime": return nextPrime(v)
        case "sinh": return sinh(v)
        case "cosh": return cosh(v)
        case "tanh": return tanh(v)
        case "cbrt": return cbrt(v)
        case "floor": return v.rounded(.down)
        case "ceil": return v.rounded(.up)
        case "round": return v.rounded(.toNearestOrAwayFromZero)
        case "trunc": return v.rounded(.towardZero)
        case "sign": return v > 0 ? 1 : v < 0 ? -1 : 0
        case "log": return log10(v)
        case "fact": return factorial(v)
        case "deg": return v * .pi / 180
        case "rad": return v
        default: return log(v)
        }
    }

    // sin π comes out as 1.2e-16, π not being a number a computer holds exactly: that is zero.
    private static func crossing(_ y: Double, _ v: Double) -> Double {
        abs(v) > 1 && abs(y) <= 1e-15 * abs(v) ? 0 : y
    }
}

// Angles are in radians unless they say otherwise: sin(x deg) and cos(35°) are in degrees, and
// asin(0.5) deg is 30. A function working in degrees is kept apart by its name, sin° for sin, so
// that an equation in it can be answered in degrees.
enum Angle {
    static let functions = ["sin", "cos", "tan"], inverses = ["asin", "acos", "atan"]

    // Whether a function gives an angle, and in degrees if so: asin and asin°.
    static func givesAngle(_ f: String) -> (degrees: Bool, Void)? {
        let name = f.hasSuffix("°") ? String(f.dropLast()) : f
        return inverses.contains(name) ? (f.hasSuffix("°"), ()) : nil
    }

    // A sine whose angle has a degree mark anywhere in it works in degrees throughout. With
    // degrees chosen in the settings every sine does, but one whose angle is marked rad or has π
    // in it, and asin answers in degrees.
    static func call(_ f: String, _ argument: Expr) -> Expr {
        if inverses.contains(f) { return .call(Options.degrees ? f + "°" : f, argument) }
        guard functions.contains(f) else { return .call(f, argument) }
        let degrees = says("deg", argument) || (Options.degrees && !says("rad", argument) && !says("π", argument))
        return .call(degrees ? f + "°" : f, unmarked(argument))
    }

    // What ° and rad after something make of it. After asin they choose what it answers in;
    // elsewhere 35° is the number of radians, and x deg and x rad are marks for a sine to find.
    static func marked(_ e: Expr, degrees: Bool) -> Expr {
        if case .call(let f, let a) = e {
            let name = f.hasSuffix("°") ? String(f.dropLast()) : f
            if inverses.contains(name) { return .call(degrees ? name + "°" : name, a) }
        }
        return .call(degrees ? "deg" : "rad", e)
    }

    // Whether the angle has in it a mark, deg or rad, or π.
    private static func says(_ mark: String, _ e: Expr) -> Bool {
        switch e {
        case .num(let v): return mark == "π" && v == .pi
        case .unknown, .index, .constant: return false
        case .neg(let a): return says(mark, a)
        case .op(_, let a, let b): return says(mark, a) || says(mark, b)
        case .apply(_, let args): return args.contains { says(mark, $0) }
        case .call(let f, let a): return f == mark || says(mark, a)
        case .sum(_, let from, let to, let body, _): return says(mark, from) || says(mark, to) || says(mark, body)
        }
    }

    private static func unmarked(_ e: Expr) -> Expr {
        switch e {
        case .num, .unknown, .index, .constant, .sum: return e
        case .neg(let a): return .neg(unmarked(a))
        case .op(let o, let a, let b): return .op(o, unmarked(a), unmarked(b))
        case .call(let f, let a): return f == "deg" || f == "rad" ? unmarked(a) : .call(f, unmarked(a))
        case .apply(let f, let args): return .apply(f, args.map(unmarked))
        }
    }
}

// n!, written after its number rather than called by name. Between the whole numbers it is
// Γ(n + 1), so that n! = 120 can be solved for n; below zero there is none.
func factorial(_ v: Double) -> Double {
    guard v >= 0 else { return .nan }
    guard v == v.rounded(), v <= 170 else { return tgamma(v + 1) }
    return v < 2 ? 1 : (2...Int(v)).reduce(1) { $0 * Double($1) }
}

// The Greek letters most often an unknown, typed by name, pasted as themselves, or as LaTeX has
// them: 2omega = 10 is solved for ω.
enum Greek {
    static let names = ["theta": "θ", "omega": "ω", "lambda": "λ", "alpha": "α", "beta": "β", "phi": "φ", "rho": "ρ", "tau": "τ", "mu": "μ"]
    static let symbols = "θωλαβφρτμ"
}

// The physical constants whose symbols are typed as they stand. A letter is one of these only
// when the equation has another letter to be its unknown: 2c = 6 is still solved for c, and
// x = 2g is 19.6.
enum Constants {
    // Each as the data booklet rounds it, which is what a mark scheme expects, and as it is known.
    static let table: [(name: String, title: String, booklet: (value: Double, text: String), precise: (value: Double, text: String))] = [
        ("g", "Acceleration of free fall", (9.8, "9.8 m s⁻²"), (9.80665, "9.80665 m s⁻²")),
        ("G", "Gravitational constant", (6.67e-11, "6.67×10⁻¹¹ N m² kg⁻²"), (6.6743e-11, "6.6743×10⁻¹¹ N m² kg⁻²")),
        ("c", "Speed of light in vacuum", (3.00e8, "3.00×10⁸ m s⁻¹"), (299_792_458, "299 792 458 m s⁻¹")),
    ]

    // Those switched on in the settings, with the values chosen there.
    static var all: [String: (value: Double, text: String)] {
        var out: [String: (value: Double, text: String)] = [:]
        for row in table where Options.constant(row.name) { out[row.name] = Options.precise ? row.precise : row.booklet }
        return out
    }

    // "g = 9.8 m s⁻², c = 3.00×10⁸ m s⁻¹", for the card and the working to say what was used.
    // ans and clip are said the same way, with the number each stands for.
    static func values(_ names: [String]) -> String {
        names.compactMap { name in (all[name]?.text ?? Memory.value(name).map(decimal)).map { "\(name) = \($0)" } }.joined(separator: ", ")
    }
}

// What is chosen in the settings window, as far as it changes an answer. Read from the defaults
// each time, so that a change there is a change in the next card.
enum Options {
    private static func flag(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }

    static var degrees: Bool { flag("degrees", false) }          // angles in degrees unless marked rad
    static var exact: Bool { flag("exact", true) }               // 5/2, √5 and π/6 where there are such, not only decimals
    static var numberFacts: Bool { flag("numberFacts", true) }   // 2048 = 2¹¹ for a number by itself
    static var matrices: Bool { flag("matrices", true) }            // det([[1,2],[3,4]]), dot, cross
    static var algebra: Bool { flag("algebra", true) }              // expand(), factor(), derivative(), integrate()
    static var inequalities: Bool { flag("inequalities", true) }   // x^2 > 4 solved for the numbers that satisfy it
    static var decimalFirst: Bool { flag("decimalFirst", true) }    // 10/4 gives 2.5, with 5/2 beneath, and not the other way
    static var basePrefix: Bool { flag("basePrefix", false) }       // 0xFF and 0b11 where it is FF and 11
    static var conversions: Bool { flag("conversions", true) }   // 5 km to miles, 255 in hex
    static var paths: Bool { flag("paths", true) }               // /Users/me/file.txt named, and shown in Finder
    static var arithmetic: Bool { flag("arithmetic", true) }     // 12*3+4 answered with no = in it
    static var precise: Bool { flag("precise", false) }          // constants as they are known, not as the booklet rounds them
    static var copyAsShown: Bool { flag("copyAsShown", false) }  // 5/2 on the pasteboard, where it would have been 2.5
    static func constant(_ name: String) -> Bool { flag("constant." + name, true) }

    // How many significant figures a decimal is given to: six, unless chosen otherwise.
    static var figures: Int {
        let chosen = UserDefaults.standard.integer(forKey: "figures")
        return chosen == 0 ? 6 : min(max(chosen, 3), 12)
    }
}

// Two numbers kept from outside what is typed: ans, the answer before this one, and clip, the
// number on the clipboard. The app sets them; a sum uses them by name, ans*2 and 20*clip.
enum Memory {
    static var answers: [Double] = []   // every answer the question before had: one, or the several roots of an equation
    static var clip: Double?

    // ans is the answer before where there was just the one. Where there were several it is no
    // one number, and they are ans1, ans2 and so on, kept here as ans_1 and ans_2, in the order
    // they were given.
    static func value(_ name: String) -> Double? {
        if name == "clip" { return clip }
        if name == "ans" { return answers.count == 1 ? answers[0] : nil }
        guard name.hasPrefix("ans_"), let i = Int(name.dropFirst(4)), i >= 1, i <= answers.count else { return nil }
        return answers[i - 1]
    }
}

struct Equation {
    var left: Expr
    var right: Expr
    var unknown: String

    var constants: [String] { unique(left.constants + right.constants) }
}

// MARK: - Parsing

enum Parser {
    struct Failure: Error {}

    enum Token: Equatable {
        case number(Double), letter(String), function(String), constant(Double)
        case named(String, Double)   // ans or clip, and the number it stands for
        case marked(String)   // !c: c read the other way round, the constant where it would have been the unknown
        case symbol(Character)
    }

    static func parse(_ input: String) throws -> Equation {
        var tokens = try tokenize(input)

        guard let roles = roles(tokens), let unknown = roles.unknown else { throw Failure() }
        tokens = tokens.map { $0 == .letter("e") && unknown != "e" && !indices(tokens).contains("e") ? .constant(M_E) : $0 }

        guard tokens.filter({ $0 == .symbol("=") }).count == 1 else { throw Failure() }
        var p = State(tokens: tokens, unknown: unknown, constants: roles.constants)
        let left = try p.expression()
        guard p.take("=") else { throw Failure() }
        let right = try p.expression()
        guard p.at == tokens.count else { throw Failure() }
        return Equation(left: left, right: right, unknown: unknown)
    }

    // Which letter is the unknown, and which are physical constants; nil where that cannot be
    // settled. With no letters there is no unknown, and the statement is one to judge.
    //
    // Exactly one letter is the unknown, not counting the k of a sum. "e" is Euler's number
    // unless it is the only letter. Where that still leaves several, those that name a physical
    // constant are that constant, so the h of h = 0.5g·3² is the unknown; and where they all do,
    // as in 2c = g, the unknown is the one standing alone on its side.
    //
    // A letter marked with ! is read the other way round from that. In 9e16 = !c^2, c would
    // have been the unknown and is the speed of light; in c = 2·!g, g would have been 9.8 and
    // is the unknown, which leaves c to be the constant.
    static func roles(_ tokens: [Token]) -> (unknown: String?, constants: Set<String>)? {
        var letters: Set<String> = [], marked: Set<String> = []
        for token in tokens {
            if case .letter(let s) = token { letters.insert(s) }
            if case .marked(let s) = token { marked.insert(s) }
        }
        letters = letters.union(marked).subtracting(indices(tokens))

        func unmarked(_ letters: Set<String>) -> (unknown: String?, constants: Set<String>)? {
            var unknowns = letters.count > 1 ? letters.subtracting(["e"]) : letters
            var constants: Set<String> = []
            if unknowns.count > 1 {
                constants = unknowns.intersection(Constants.all.keys)
                unknowns.subtract(constants)
                if unknowns.isEmpty, let alone = subject(tokens), constants.contains(alone) {
                    unknowns = [alone]
                    constants.remove(alone)
                }
            }
            guard unknowns.count == 1 || letters.isEmpty else { return nil }
            return (unknowns.first, constants)
        }
        guard !marked.isEmpty else { return unmarked(letters) }

        let usual = unmarked(letters)
        let nowUnknown = marked.filter { usual?.unknown != $0 }, nowConstant = marked.subtracting(nowUnknown)
        if let unknown = nowUnknown.first {
            let others = letters.subtracting([unknown, "e"])
            guard nowUnknown.count == 1, others.allSatisfy({ Constants.all[$0] != nil }) else { return nil }
            return (unknown, others)
        }
        guard let rest = unmarked(letters.subtracting(nowConstant)) else { return nil }
        return (rest.unknown, rest.constants.union(nowConstant))
    }

    // The letter that is the whole of one side of an equation, the left for preference.
    static func subject(_ tokens: [Token]) -> String? {
        for side in tokens.split(separator: .symbol("="), omittingEmptySubsequences: false) where side.count == 1 {
            if case .letter(let s)? = side.first { return s }
            if case .marked(let s)? = side.first { return s }
        }
        return nil
    }

    // An expression of numbers alone, read from tokens whose letters have had their parts
    // settled: only constants, functions and sums beside the numbers.
    static func expression(_ tokens: [Token], constants: Set<String>) throws -> Expr {
        var p = State(tokens: tokens, unknown: "", constants: constants)
        let e = try p.expression()
        guard p.at == tokens.count else { throw Failure() }
        return e
    }

    // An expression with no unknown in it, only numbers, constants, functions and sums. A letter
    // that names a physical constant is that constant, unless it is the name being given a value:
    // x = 2g is 19.6, and g = 2g is an equation in g. Nor where it is marked with !, which makes
    // it the unknown.
    static func constant(_ input: String, naming name: String? = nil, physical: Bool = true) throws -> Expr {
        var tokens = try tokenize(input)
        let ks = indices(tokens)
        tokens = tokens.map { $0 == .letter("e") && !ks.contains("e") ? .constant(M_E) : $0 }
        let constants = physical ? Set(Constants.all.keys).subtracting(ks).subtracting([name].compactMap { $0 }) : []
        guard !tokens.contains(where: {
            switch $0 {
            case .letter(let s): !ks.contains(s) && !constants.contains(s)
            case .marked: true
            default: false
            }
        }), !tokens.contains(.symbol("=")) else { throw Failure() }
        var p = State(tokens: tokens, unknown: "", constants: constants)
        let e = try p.expression()
        guard p.at == tokens.count else { throw Failure() }
        return e
    }

    // The letters that are a sum's k: sum(k, from, to, term).
    static func indices(_ tokens: [Token]) -> Set<String> {
        var ks: Set<String> = []
        for i in tokens.indices.dropLast(2) {
            guard tokens[i] == .function("sum") || tokens[i] == .function("prod"), tokens[i + 1] == .symbol("("),
                  case .letter(let k) = tokens[i + 2] else { continue }
            ks.insert(k)
        }
        return ks
    }

    static func tokenize(_ input: String) throws -> [Token] {
        let replacements: [(String, String)] = [
            ("×", "*"), ("·", "*"), ("÷", "/"), ("−", "-"), ("⁻¹", "^-1"), ("²", "^2"), ("³", "^3"), ("π", "pi"), ("√", "sqrt"), ("∛", "cbrt"),
            ("arcsin", "asin"), ("arccos", "acos"), ("arctan", "atan"),
        ]
        // Capitals are kept: G is not g, and E is a letter where e is Euler's number.
        var s = input
        // x⁴ and 10⁻³: a run of raised digits is a power.
        let raised: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
        if s.contains(where: { raised[$0] != nil }) {
            var out = "", inPower = false
            for c in s {
                if let plain = raised[c] { if !inPower { out += "^"; inPower = true }; out.append(plain) } else { inPower = false; out.append(c) }
            }
            s = out
        }
        for (from, to) in replacements { s = s.replacingOccurrences(of: from, with: to) }

        // 15% of 80 is 15% times 80.
        s = s.replacingOccurrences(of: "%\\s*of\\s+", with: "%*", options: [.regularExpression, .caseInsensitive])

        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == " " {
                i = s.index(after: i)
            } else if c.isNumber || c == "." {
                var j = i
                while j < s.endIndex, s[j].isNumber || s[j] == "." { j = s.index(after: j) }
                // 5.97e24, 1.6E-19: an e straight after the digits, with digits after it, is a
                // power of ten. Spaced out, as 2e - 3, it is still a letter.
                if j < s.endIndex, s[j] == "e" || s[j] == "E" {
                    var k = s.index(after: j)
                    if k < s.endIndex, s[k] == "-" || s[k] == "+" { k = s.index(after: k) }
                    let digits = k
                    while k < s.endIndex, s[k].isASCII, s[k].isNumber { k = s.index(after: k) }
                    if k > digits { j = k }
                }
                guard let v = Double(s[i..<j]) else { throw Failure() }
                tokens.append(.number(v))
                i = j
            } else if c.isLetter, c.isASCII {
                var j = i
                while j < s.endIndex, s[j].isLetter, s[j].isASCII { j = s.index(after: j) }
                // The digits straight after, for ans2, which is not ans times 2.
                var k = j
                while k < s.endIndex, s[k].isASCII, s[k].isNumber { k = s.index(after: k) }
                let (read, numbered) = try splitLetters(String(s[i..<j]), then: String(s[j..<k]))
                tokens += read
                i = try attachSubscript(&tokens, s, numbered ? k : j)
            } else if Greek.symbols.contains(c) {
                tokens.append(.letter(String(c)))
                i = try attachSubscript(&tokens, s, s.index(after: i))
            } else if c == "°" {
                tokens.append(.symbol(c))
                i = s.index(after: i)
            } else if c == "!", !endsOperand(tokens), let next = s[s.index(after: i)...].first, Constants.all[String(next)] != nil {
                // After a number or a bracket ! is a factorial. With nothing before it to be
                // one of, it marks the letter after it to be read the other way round: 9e16 = !c^2
                // is about the speed of light, where 9e16 = c^2 would be solved for c.
                tokens.append(.marked(String(next)))
                i = s.index(i, offsetBy: 2)
            } else if "+-*/^()=,!%".contains(c) || Binary.table[c] != nil {
                tokens.append(.symbol(c))
                i = s.index(after: i)
            } else {
                throw Failure()
            }
        }
        return tokens
    }

    // F_n and v_0: a subscript makes the letter before it a letter of its own, F_n, not F. It is
    // letters or digits, not both, so that v_0t is v_0 times t. Returns where reading goes on.
    static func attachSubscript(_ tokens: inout [Token], _ s: String, _ i: String.Index) throws -> String.Index {
        guard i < s.endIndex, s[i] == "_" else { return i }
        let start = s.index(after: i)
        guard start < s.endIndex, s[start].isASCII, s[start].isLetter || s[start].isNumber,
              case .letter(let name)? = tokens.last else { throw Failure() }
        let digits = s[start].isNumber
        var j = start
        while j < s.endIndex, s[j].isASCII, digits ? s[j].isNumber : s[j].isLetter { j = s.index(after: j) }
        tokens[tokens.count - 1] = .letter(name + "_" + s[start..<j])
        return j
    }

    // Whether what has been read so far ends in something a factorial could be of.
    static func endsOperand(_ tokens: [Token]) -> Bool {
        switch tokens.last {
        case .number, .letter, .constant, .named, .marked, .symbol(")"), .symbol("!"), .symbol("°"), .symbol("㎭"): true
        default: false
        }
    }

    // "sinx" is sin x and "2nx" would be n times x: known names first, then single letters.
    // digits are what follows the letters; numbered says they were used up, as the 2 of ans2.
    static func splitLetters(_ run: String, then digits: String = "") throws -> (tokens: [Token], numbered: Bool) {
        var run = run
        // SIN, Sqrt and NCR are the functions all the same; Mean(1,2,3) too.
        if run.contains(where: \.isUppercase), run.count > 1, (["sum", "prod", "pi"] + Functions.names).contains(run.lowercased()) { run = run.lowercased() }
        var out: [Token] = []
        var rest = Substring(run)
        var numbered = false
        while !rest.isEmpty {
            if let f = (["sum", "prod"] + Functions.names.sorted { $0.count > $1.count }).first(where: { rest.hasPrefix($0) }) {
                out.append(.function(f))
                rest = rest.dropFirst(f.count)
            } else if rest.hasPrefix("pi") {
                out.append(.constant(.pi))
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("deg") {
                out.append(.symbol("°"))
                rest = rest.dropFirst(3)
            } else if let word = ["ans", "Ans", "clip"].first(where: { rest.hasPrefix($0) }) {
                // With no answer yet, or no number on the clipboard, there is nothing to say.
                var name = word.lowercased()
                if name == "ans", rest.count == word.count, !digits.isEmpty {
                    name = "ans_" + digits
                    numbered = true
                }
                guard let value = Memory.value(name) else { throw Failure() }
                out.append(.named(name, value))
                rest = rest.dropFirst(word.count)
            } else if rest.hasPrefix("rad") {
                out.append(.symbol("㎭"))
                rest = rest.dropFirst(3)
            } else if let (name, symbol) = Greek.names.first(where: { rest.hasPrefix($0.key) }) {
                out.append(.letter(symbol))
                rest = rest.dropFirst(name.count)
            } else {
                out.append(.letter(String(rest.first!)))
                rest = rest.dropFirst()
            }
        }
        return (out, numbered)
    }

    struct State {
        let tokens: [Token]
        let unknown: String
        var constants: Set<String> = []   // the letters read as physical constants
        var at = 0
        var bound: [String] = []   // the k of each sum being read
        var percent: (start: Int, end: Int)?   // the tokens of the last n%, to see whether it stands alone

        var next: Token? { at < tokens.count ? tokens[at] : nil }

        mutating func take(_ c: Character) -> Bool {
            if next == .symbol(c) { at += 1; return true }
            return false
        }

        mutating func expression() throws -> Expr {
            var e = try term()
            while true {
                let sign: Character
                if take("+") { sign = "+" } else if take("-") { sign = "-" } else { return e }
                let begins = at
                let t = try term()
                // 200 + 10% is 200 and a tenth of it more, as a calculator reads it; 200 + 50 * 10%
                // is not, the percentage there being of 50.
                if let p = percent, p.start == begins, p.end == at {
                    e = .op("*", e, .op(sign, .num(1), t))
                } else {
                    e = .op(sign, e, t)
                }
            }
        }

        // Juxtaposition multiplies, as on paper: 2n, 2(n+1), (x+1)(x-1), 3sin x.
        mutating func term() throws -> Expr {
            var e = try unary()
            while true {
                if take("*") { e = .op("*", e, try unary()) }
                else if take("/") { e = .op("/", e, try unary()) }
                else if take("%") { e = .op("%", e, try unary()) }
                else if case .symbol(let c)? = next, Binary.table[c] != nil { at += 1; e = .op(c, e, try unary()) }
                else if startsOperand { e = .op("*", e, try power()) }
                else { return e }
            }
        }

        // 10 % 3 is a remainder; 10% is a tenth. It is the remainder when an operand follows.
        func startsOperand(after i: Int) -> Bool {
            switch i + 1 < tokens.count ? tokens[i + 1] : nil {
            case .number, .letter, .function, .constant, .named, .marked, .symbol("("): true
            default: false
            }
        }

        var startsOperand: Bool {
            switch next {
            case .number, .letter, .function, .constant, .named, .marked, .symbol("("): true
            default: false
            }
        }

        mutating func unary() throws -> Expr {
            if take("-") { return .neg(try unary()) }
            if take("+") { return try unary() }
            return try power()
        }

        // 5! binds before a power does: 2^3! is 2⁶, and n!^2 is (n!)².
        mutating func power() throws -> Expr {
            let start = at
            var base = try primary()
            // 35° and x deg say degrees, to the sine they are inside; x rad says radians, as it
            // would have been anyway.
            while true {
                if take("!") { base = .call("fact", base) }
                else if take("°") { base = Angle.marked(base, degrees: true) }
                else if take("㎭") { base = Angle.marked(base, degrees: false) }
                else if next == .symbol("%"), !startsOperand(after: at) { at += 1; base = .op("/", base, .num(100)); percent = (start, at) }
                else { break }
            }
            return take("^") ? .op("^", base, try unary()) : base
        }

        // What a function is of when it is written without brackets: sin 2x is of 2x, with what
        // is written straight after taken in, and tan⁻¹ 24/21 is of the fraction. It stops at
        // another function, so that sin x cos x is two; and sin x/2 is half of sin x.
        mutating func bare() throws -> Expr {
            let negative = take("-")
            var e = try power()
            if negative { e = .neg(e) }
            if case .num = e, next == .symbol("/"), at + 1 < tokens.count, case .number(let below) = tokens[at + 1] {
                at += 2
                e = .op("/", e, .num(below))
            }
            while true {
                switch next {
                case .number, .letter, .constant, .named, .marked, .symbol("("): e = .op("*", e, try power())
                default: return e
                }
            }
        }

        mutating func primary() throws -> Expr {
            guard let t = next else { throw Failure() }
            at += 1
            switch t {
            case .number(let v), .constant(let v): return .num(v)
            case .named(let name, let v): return .constant(name, v)
            case .letter(let s), .marked(let s):
                if bound.contains(s) { return .index(s) }
                if constants.contains(s), let known = Constants.all[s] { return .constant(s, known.value) }
                return .unknown
            // sum(k, from, to, term), and prod the same.
            case .function(let f) where f == "sum" || f == "prod":
                guard take("("), case .letter(let k)? = next else { throw Failure() }
                at += 1
                guard take(",") else { throw Failure() }
                let from = try expression()
                guard take(",") else { throw Failure() }
                let to = try expression()
                guard take(",") else { throw Failure() }
                bound.append(k)
                let body = try expression()
                bound.removeLast()
                guard take(")") else { throw Failure() }
                return .sum(k, from: from, to: to, body, product: f == "prod")
            // mean(2, 4, 9): any number of arguments, in brackets.
            case .function(let f) where Lists.names.contains(f):
                guard take("(") else { throw Failure() }
                var args = [try expression()]
                while take(",") { args.append(try expression()) }
                guard take(")"), Lists.accepts(f, args.count) else { throw Failure() }
                return .apply(f, args)
            // sin(x)^2 is (sin x)², as written on paper; sin x^2 is sin(x²).
            case .function(let f):
                // A power written on the function itself: sin^2 x is (sin x)², and tan^-1 x, as
                // LaTeX's \tan^{-1} comes, is the angle whose tangent is x.
                let raised = take("^") ? try unary() : nil
                var argument: Expr
                if take("(") {
                    argument = try expression()
                    guard take(")") else { throw Failure() }
                } else {
                    argument = try bare()
                }
                // sec, csc and cot are one over cos, sin and tan, and so are in degrees where they are.
                if let base = ["sec": "cos", "csc": "sin", "cot": "tan"][f] {
                    let reciprocal = Expr.op("/", .num(1), Angle.call(base, argument))
                    return raised.map { .op("^", reciprocal, $0) } ?? reciprocal
                }
                guard let raised else { return Angle.call(f, argument) }
                var inverse = false
                if case .neg(.num(1)) = raised { inverse = true }
                if inverse, Angle.functions.contains(f) { return Angle.call("a" + f, argument) }
                return .op("^", Angle.call(f, argument), raised)
            case .symbol("("):
                let e = try expression()
                guard take(")") else { throw Failure() }
                return e
            default: throw Failure()
            }
        }
    }
}

// MARK: - Polynomials (coefficients from the constant term up)

typealias Poly = [Double]

func poly(_ e: Expr) -> Poly? {
    switch e {
    case .num(let v), .constant(_, let v): return [v]
    case .unknown: return [0, 1]
    case .index: return nil
    case .apply(_, let args):
        guard args.allSatisfy({ !$0.hasUnknown }) else { return nil }
        return [e.eval(0)]
    // A sum of polynomials is one, term by term, as long as it has a fixed, modest number of terms.
    case .sum(let k, let from, let to, let body, let product):
        guard let a = poly(from).map(trim), a.count <= 1, let b = poly(to).map(trim), b.count <= 1,
              let range = Expr.range(a.first ?? 0, b.first ?? 0), range.count <= 1000 else { return nil }
        var total: Poly = product ? [1] : []
        for i in range {
            guard let term = poly(body.setting(k, to: Double(i))).map(trim) else { return nil }
            total = product ? mul(total, term) : add(total, term)
            if total.count > 32 { return nil }
        }
        return total
    case .neg(let a): return poly(a).map { $0.map { -$0 } }
    case .call(let f, let a):
        guard let p = poly(a).map(trim), p.count <= 1 else { return nil }
        return [Functions.apply(f, p.first ?? 0)]
    case .op(let o, let a, let b):
        guard let l = poly(a).map(trim), let r = poly(b).map(trim) else { return nil }
        switch o {
        case "+": return add(l, r)
        case "-": return sub(l, r)
        case "*": return l.count + r.count > 32 ? nil : mul(l, r)
        case "/":
            guard r.count == 1, r[0] != 0 else { return nil }
            return l.map { $0 / r[0] }
        case _ where Binary.table[o] != nil:
            guard l.count <= 1, r.count <= 1 else { return nil }
            return [Expr.op(o, .num(l.first ?? 0), .num(r.first ?? 0)).eval(0)]
        default:
            guard r.count <= 1 else { return nil }
            let k = r.first ?? 0
            if l.count <= 1 { return [pow(l.first ?? 0, k)] }
            guard k >= 0, k <= 16, k == k.rounded() else { return nil }
            return (0..<Int(k)).reduce([1]) { acc, _ in mul(acc, l) }
        }
    }
}

func add(_ a: Poly, _ b: Poly) -> Poly {
    (0..<max(a.count, b.count)).map { added(a.indices.contains($0) ? a[$0] : 0, b.indices.contains($0) ? b[$0] : 0) }
}

func sub(_ a: Poly, _ b: Poly) -> Poly { add(a, b.map { -$0 }) }

func mul(_ a: Poly, _ b: Poly) -> Poly {
    guard !a.isEmpty, !b.isEmpty else { return [] }
    var out = Poly(repeating: 0, count: a.count + b.count - 1)
    for i in a.indices { for j in b.indices { out[i + j] = added(out[i + j], a[i] * b[j]) } }
    return out
}

// Drops leading coefficients that are zero. Rounding noise has already gone, as the terms were
// added up, so 0.1x + 0.2x − 0.3x has nothing left, and a coefficient of 6.63e-34 is kept.
func trim(_ p: Poly) -> Poly {
    var p = p
    while p.last == 0 { p.removeLast() }
    return p
}

// MARK: - Solving

func solvePolynomial(_ p: Poly, _ name: String, exact: Bool = true) -> Solution {
    switch p.count {
    case 0: return Solution(exact: "\(name) ∈ ℝ", approx: "Every real number satisfies the equation.")
    case 1: return Solution(exact: "No solution", approx: nil)
    default:
        if exact, p.count <= 3, let ints = integerCoefficients(p) { return exactSolution(ints, name) }
        return listRoots(realRoots(p), name, more: false)
    }
}

// Rational coefficients scaled to integers, small enough that b² - 4ac cannot overflow.
func integerCoefficients(_ p: Poly) -> [Int]? {
    var fractions: [(Int, Int)] = []
    for c in p {
        // A coefficient too small to tell from zero is not zero: 6.63e-34 stays a decimal.
        guard let f = rational(c), f.0 != 0 || c == 0 else { return nil }
        fractions.append(f)
    }
    let l = fractions.reduce(1) { lcm($0, $1.1) }
    guard l <= 1_000_000 else { return nil }
    let ints = fractions.map { $0.0 * (l / $0.1) }   // |p| < 1e10 and l/q ≤ 1e6: no overflow
    guard ints.allSatisfy({ abs($0) <= 1_000_000 }) else { return nil }
    let g = ints.reduce(0) { gcd($0, $1) }
    return ints.map { $0 / max(g, 1) }
}

func exactSolution(_ c: [Int], _ name: String) -> Solution {
    if c.count == 2 {
        let root = fraction(-c[0], c[1])
        return Solution(exact: "\(name) = \(root)", approx: root.contains("/") ? "≈ \(decimal(-Double(c[0]) / Double(c[1])))" : nil)
    }
    let (a, b, cc) = (c[2], c[1], c[0])
    let d = b * b - 4 * a * cc
    if d < 0 {
        let (exact, decimals) = complexQuadratic(a, b, d)
        let needsDecimals = exact.contains("√") || exact.contains("/")
        return Solution(exact: "\(name) = \(exact)", approx: needsDecimals ? "≈ \(decimals); no real solutions" : "No real solutions; the roots are complex")
    }
    if d == 0 {
        let root = fraction(-b, 2 * a)
        return Solution(exact: "\(name) = \(root)", approx: root.contains("/") ? "≈ \(decimal(-Double(b) / Double(2 * a)))" : nil)
    }
    let (k, m) = squareFactor(d)
    let roots = [(-Double(b) - Double(d).squareRoot()) / Double(2 * a), (-Double(b) + Double(d).squareRoot()) / Double(2 * a)].sorted()
    if m == 1, b == 0 {
        let root = fraction(k, abs(2 * a))
        return Solution(exact: "\(name) = ±\(root)", approx: root.contains("/") ? "≈ ±\(decimal(abs(roots[0])))" : nil)
    }
    if m == 1 {
        let r = [fraction(-b - k, 2 * a), fraction(-b + k, 2 * a)]
        let ordered = (-Double(b) - Double(k)) / Double(2 * a) < (-Double(b) + Double(k)) / Double(2 * a) ? r : r.reversed()
        let needsApprox = ordered.contains { $0.contains("/") }
        return Solution(exact: "\(name) = \(ordered.joined(separator: ", "))",
                        approx: needsApprox ? "≈ \(roots.map(decimal).joined(separator: ", "))" : nil)
    }
    let (bb, kk, _, den) = radicalForm(a, b, d)
    let radical = (kk == 1 ? "" : "\(kk)") + "√\(m)"
    let exact: String
    if bb == 0 {
        exact = "±" + radical + (den == 1 ? "" : "/\(den)")
    } else {
        exact = den == 1 ? "\(minus(bb)) ± \(radical)" : "(\(minus(bb)) ± \(radical))/\(den)"
    }
    let approx = bb == 0 ? "≈ ±\(decimal(abs(roots[0])))" : "≈ \(roots.map(decimal).joined(separator: ", "))"
    return Solution(exact: "\(name) = \(exact)", approx: approx)
}

// The roots of ax² + bx + c with discriminant d < 0, as (−1 ± √3 i)/2: written exactly, and as decimals.
func complexQuadratic(_ a: Int, _ b: Int, _ d: Int) -> (exact: String, decimals: String) {
    let (bb, kk, m, den) = radicalForm(a, b, -d)
    let re = Double(bb) / Double(den), im = Double(kk) * Double(m).squareRoot() / Double(den)
    let decimals = re == 0 ? "±\(im == 1 ? "" : decimal(im))i" : "\(decimal(re)) ± \(im == 1 ? "" : decimal(im))i"
    if m == 1 {
        let imaginary = den == 1 ? (kk == 1 ? "i" : "\(kk)i") : (kk == 1 ? "i/\(den)" : "\(kk)i/\(den)")
        return (bb == 0 ? "±\(imaginary)" : "\(fraction(bb, den)) ± \(imaginary)", decimals)
    }
    let radical = (kk == 1 ? "" : "\(kk)") + "√\(m) i"
    if bb == 0 { return ("±" + radical + (den == 1 ? "" : "/\(den)"), decimals) }
    return (den == 1 ? "\(minus(bb)) ± \(radical)" : "(\(minus(bb)) ± \(radical))/\(den)", decimals)
}

// The roots of ax² + bx + c with discriminant d > 0 as (bb ± kk√m)/den: d = k²m with m
// square-free, and whatever divides -b, k and 2a taken out.
func radicalForm(_ a: Int, _ b: Int, _ d: Int) -> (bb: Int, kk: Int, m: Int, den: Int) {
    let (k, m) = squareFactor(d)
    let g = gcd(gcd(abs(b), k), abs(2 * a))
    var (bb, kk, den) = (-b / g, k / g, 2 * a / g)
    if den < 0 { bb = -bb; den = -den }
    return (bb, kk, m, den)
}

func solveNumerically(_ eq: Equation, _ name: String) -> Solution? {
    // log n = 5 has its answer worked out directly; the search below only reaches ±1000.
    if let root = closedRoot(eq) {
        if root.value.isFinite, root.value != 0 || root.power == nil { return listRoots([root.value], name, more: false) }
        if let power = root.power {
            return Solution(exact: "\(name) = \(power.plain)", approx: "Too \(root.value == 0 ? "small" : "large") to be written out as a decimal.")
        }
    }
    guard let roots = numericRoots(eq) else { return nil }
    if roots.isEmpty { return Solution(exact: "No real solutions found", approx: "The interval −1000 ≤ \(name) ≤ 1000 was searched.") }
    // An angle is given for one turn from zero, in degrees and in radians.
    if let unit = angleUnit(eq) {
        let turn = roots.filter { $0 >= 0 && $0 <= unit.turn * (1 + 1e-12) }.sorted()
        if !turn.isEmpty { return angleCard(name, Array(turn.prefix(4)), more: turn.count > 4, unit) }
    }
    // The four nearest zero, and the other half of a ± pair when the fourth is one.
    let nearest = roots.sorted { abs($0) < abs($1) }
    let cutoff = abs(nearest[min(3, nearest.count - 1)]) * (1 + 1e-9)
    let shown = nearest.filter { abs($0) <= cutoff }
    return listRoots(shown, name, more: roots.count > shown.count)
}

// Every real root on -1000...1000, or nil when the equation is undefined all the way along.
func numericRoots(_ eq: Equation) -> [Double]? {
    let f = { (x: Double) in eq.left.eval(x) - eq.right.eval(x) }
    var roots: [Double] = []
    var sawValue = false

    func accept(_ x: Double, touching: Bool = false) {
        let y = f(x)
        // A curve that only touches zero is at its lowest there: on both sides it is higher. One
        // that merely dies away, as 3ˣ does to the left, is not at a root anywhere.
        if touching, y.isFinite {
            let h = 1e-3 * max(1, abs(x))
            let (a, b) = (abs(f(x - h)), abs(f(x + h)))
            guard a.isFinite, b.isFinite, a > abs(y), b > abs(y) else { return }
        }
        guard y.isFinite, abs(y) <= 1e-7 * max(1, abs(eq.left.eval(x))) else { return }
        // Both sides gone to nothing, far out (2^(x+1) = 3^x at x = −1000): they are equal to the
        // machine only because neither can be told from zero.
        if abs(x) > 1, max(abs(eq.left.eval(x)), abs(eq.right.eval(x))) < 1e-100 {
            let h = 1e-3 * abs(x)
            if abs(f(x - h)) < 1e-100, abs(f(x + h)) < 1e-100 { return }
        }
        if !roots.contains(where: { abs($0 - x) <= 1e-7 * max(1, abs(x)) }) { roots.append(x) }
    }

    // A fine grid near zero and a coarse one out to ±1000; sign changes are bisected, and
    // dips that touch zero without crossing it (sin²x = 0) are polished with Newton's method.
    // Zero itself is tried first: with nothing defined to its left, as in √x = 0 and n! = 1,
    // there is no change of sign to find it by.
    if f(0) == 0 { accept(0) }
    for (range, step) in [(10.0, 0.001), (1000.0, 0.05)] {
        var x0 = -range, y0 = f(x0)
        var prevAbs = Double.infinity
        while x0 < range {
            let x1 = x0 + step, y1 = f(x1)
            if y0.isFinite { sawValue = true }
            if y0 == 0 { accept(x0) }
            else if y0.isFinite, y1.isFinite, y0.sign != y1.sign { accept(bisect(f, x0, x1)) }
            if y0.isFinite, abs(y0) < prevAbs, y1.isFinite, abs(y1) > abs(y0), abs(y0) < 1e-2 { accept(newton(f, x0), touching: true) }
            prevAbs = y0.isFinite ? abs(y0) : .infinity
            x0 = x1; y0 = y1
        }
    }
    guard sawValue else { return nil }
    return roots.map { abs($0) < 1e-7 ? 0 : $0 }   // a root at 0 found as 1e-9
}

func listRoots(_ roots: [Double], _ name: String, more: Bool) -> Solution {
    if roots.isEmpty { return Solution(exact: "No real solutions", approx: nil) }
    let sorted = roots.sorted()
    let symmetric = sorted.count == 2 && abs(sorted[0] + sorted[1]) <= 1e-9 * abs(sorted[1])
    let text = symmetric ? "±\(decimal(sorted[1]))" : sorted.map(decimal).joined(separator: ", ")
    let allIntegers = sorted.allSatisfy(isExact)
    return Solution(exact: "\(name) \(allIntegers ? "=" : "≈") \(text)\(more ? ", …" : "")",
                    approx: more ? "Further solutions exist; those nearest to 0 are shown." : nil)
}

func bisect(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> Double {
    var (a, b, fa) = (a, b, f(a))
    for _ in 0..<80 {
        let m = (a + b) / 2, fm = f(m)
        if fm == 0 { return m }
        if fa.sign == fm.sign { a = m; fa = fm } else { b = m }
    }
    return (a + b) / 2
}

func newton(_ f: (Double) -> Double, _ start: Double) -> Double {
    var x = start
    for _ in 0..<50 {
        let y = f(x), h = 1e-7 * max(1, abs(x))
        let slope = (f(x + h) - f(x - h)) / (2 * h)
        guard slope.isFinite, slope != 0 else { break }
        let step = y / slope
        x -= step
        if abs(step) < 1e-14 * max(1, abs(x)) { break }
    }
    return x
}

// Real roots of a polynomial of any degree: Durand–Kerner for all roots, then the real ones polished.
func realRoots(_ p: Poly) -> [Double] {
    // A root at zero is taken out exactly. The rest are found as multiples of a bound on the
    // largest (Fujiwara's), and to so many figures rather than so many decimal places, so that
    // the radius of an orbit and the charge on an electron are found as well as 2 and 3 are.
    // The bound is rounded up to a power of two, which costs the coefficients no accuracy.
    var p = p
    var zero: [Double] = []
    while p.count > 1, p[0] == 0 {
        p.removeFirst()
        zero = [0]
    }
    let n = p.count - 1
    guard n >= 1 else { return zero }
    let lead = p[n]
    let bound = 2 * (0..<n).map { pow(abs(p[$0] / lead) / ($0 == 0 ? 2 : 1), 1 / Double(n - $0)) }.max()!
    let shift = Int(log2(bound).rounded(.up))
    let c = (0...n).map { scalbn(p[$0] / lead, shift * ($0 - n)) }
    func eval(_ z: (Double, Double)) -> (Double, Double) {
        var r = (0.0, 0.0)
        for k in stride(from: n, through: 0, by: -1) { r = (r.0 * z.0 - r.1 * z.1 + c[k], r.0 * z.1 + r.1 * z.0) }
        return r
    }
    // Starting points: powers of 0.4 + 0.9i, spread out to the bound on the roots' size.
    let radius = 1 + c.dropLast().map(abs).max()!
    var z: [(Double, Double)] = []
    var w = (1.0, 0.0)
    for _ in 0..<n {
        z.append((w.0 * radius, w.1 * radius))
        w = (w.0 * 0.4 - w.1 * 0.9, w.0 * 0.9 + w.1 * 0.4)
    }
    for _ in 0..<500 {
        var moved = 0.0
        for i in 0..<n {
            var den = (1.0, 0.0)
            for j in 0..<n where j != i {
                let d = (z[i].0 - z[j].0, z[i].1 - z[j].1)
                den = (den.0 * d.0 - den.1 * d.1, den.0 * d.1 + den.1 * d.0)
            }
            let num = eval(z[i]), mag = den.0 * den.0 + den.1 * den.1
            guard mag > 0 else { continue }
            let step = ((num.0 * den.0 + num.1 * den.1) / mag, (num.1 * den.0 - num.0 * den.1) / mag)
            z[i] = (z[i].0 - step.0, z[i].1 - step.1)
            moved = max(moved, (abs(step.0) + abs(step.1)) / max(abs(z[i].0) + abs(z[i].1), .leastNormalMagnitude))
        }
        if moved < 1e-14 { break }
    }
    // A root of multiplicity m comes out as m roots in a ring round it, wider the more there are
    // (a sixth power's are a thousandth of its size apart). Their mean is the root, to the last
    // figure; it is taken for one where the polynomial is nothing there.
    var clustered = Set<Int>()
    for i in 0..<n where !clustered.contains(i) {
        let tolerance = 0.03 * max(abs(z[i].0) + abs(z[i].1), 1e-2)
        let near = (0..<n).filter { abs(z[$0].0 - z[i].0) + abs(z[$0].1 - z[i].1) <= tolerance }
        guard near.count >= 2 else { continue }
        let centre = (near.reduce(0.0) { $0 + z[$1].0 } / Double(near.count), near.reduce(0.0) { $0 + z[$1].1 } / Double(near.count))
        // The ring is not quite symmetrical, but its mean is on the line to within what it is wide.
        let (re, im) = eval((centre.0, 0))
        guard abs(centre.1) <= 1e-2 * (abs(centre.0) + 1e-3), abs(re) + abs(im) <= 1e-9 else { continue }
        // The m-fold root of p is a simple root of its (m − 1)th derivative: Newton's method there
        // takes the mean to the root itself.
        var q = Array(p)
        for _ in 0..<(near.count - 1) { q = q.enumerated().dropFirst().map { Double($0.offset) * $0.element } }
        let dq = q.enumerated().dropFirst().map { Double($0.offset) * $0.element }
        var x = scalbn(centre.0, shift)
        func horner(_ c: [Double], _ x: Double) -> Double { c.reversed().reduce(0) { $0 * x + $1 } }
        for _ in 0..<40 {
            let slope = horner(dq, x)
            guard slope != 0, slope.isFinite else { break }
            let step = horner(q, x) / slope
            guard abs(step) <= 1e-2 * max(abs(x), 1e-3) else { break }
            x -= step
            if abs(step) <= 1e-15 * abs(x) { break }
        }
        for j in near { z[j] = (scalbn(x, -shift), 0); clustered.insert(j) }
    }
    // Each real root is taken back to its own size and polished there, by Newton's method on
    // the polynomial as given and its derivative, both by Horner's rule. A whole number that is
    // exactly a root is that root: a repeated one, the 1 of (x − 1)³, is otherwise only found
    // to a few figures.
    func value(_ x: Double) -> (Double, slope: Double) {
        var value = 0.0, slope = 0.0
        for k in stride(from: n, through: 0, by: -1) {
            slope = slope * x + value
            value = value * x + p[k]
        }
        return (value, slope)
    }
    var roots: [Double] = []
    for r in z where abs(r.1) <= 1e-3 * (abs(r.0) + abs(r.1)) {
        let real = abs(r.1) <= 1e-6 * (abs(r.0) + abs(r.1))
        var x = scalbn(r.0, shift)
        let start = x
        for _ in 0..<(real ? 50 : 0) {
            let (y, slope) = value(x)
            guard slope.isFinite, slope != 0 else { break }
            // At a repeated root the slope is nothing and the step wild: it must not carry the
            // estimate off to another root.
            guard abs(y / slope) <= 1e-4 * max(abs(start), .leastNormalMagnitude) else { break }
            x -= y / slope
            if abs(y / slope) <= 1e-15 * abs(x) { break }
        }
        let whole = x.rounded()
        if abs(x - whole) <= 1e-3 * abs(x), value(whole).0 == 0 { x = whole } else if !real { continue }
        if !roots.contains(where: { abs($0 - x) <= 1e-7 * abs(x) }) { roots.append(x) }
    }
    return zero + roots
}

// MARK: - Numbers

func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
func lcm(_ a: Int, _ b: Int) -> Int { a / gcd(a, b) * b }

// The fraction p/q (q up to 1000) a coefficient is, if it is one.
func rational(_ x: Double) -> (Int, Int)? {
    guard x.isFinite, abs(x) < 1e7 else { return nil }
    for q in 1...1000 {
        let p = (x * Double(q)).rounded()
        if abs(p / Double(q) - x) <= 1e-9 * max(1, abs(x)) { return (Int(p), q) }
    }
    return nil
}

// d = k² m with m square-free.
func squareFactor(_ d: Int) -> (Int, Int) {
    var k = 1, m = d, f = 2
    while f * f <= m {
        while m % (f * f) == 0 { m /= f * f; k *= f }
        f += 1
    }
    return (k, m)
}

func fraction(_ p: Int, _ q: Int) -> String {
    let g = gcd(p, q)
    var (p, q) = (p / max(g, 1), q / max(g, 1))
    if q < 0 { p = -p; q = -q }
    return q == 1 ? minus(p) : "\(minus(p))/\(q)"
}

func minus(_ n: Int) -> String { n < 0 ? "−\(-n)" : "\(n)" }

// Whether decimal(x) is x itself rather than x rounded: a whole number, or, where it is written
// as a power of ten, one of six figures at most. It decides between = and ≈.
func isExact(_ x: Double) -> Bool {
    let size = abs(x)
    if x == 0 || (size >= 1e-6 && size < 1e12) { return abs(x - x.rounded()) < 1e-9 }
    guard let shown = Double(String(format: "%.\(Options.figures - 1)e", x)) else { return false }
    return abs(shown - x) <= 1e-12 * size
}

// Six significant figures, or as many as the settings ask for, with a real minus sign: written out where that can be read, and as
// 6.67×10⁻¹¹ where it cannot, which is the very large, the very small, and round numbers from ten
// million up (3×10⁸, but 12345678).
func decimal(_ x: Double) -> String {
    if x == 0 { return "0" }
    guard x.isFinite else { return String(format: "%.6g", x).replacingOccurrences(of: "-", with: "−") }
    let size = abs(x)
    let round = size >= 1e7 && size < 1e12 && x == x.rounded() && String(Int(size)).reversed().drop(while: { $0 == "0" }).count <= 4
    if size >= 1e12 || size < 1e-6 || round {
        let parts = String(format: "%.\(Options.figures - 1)e", x).split(separator: "e")
        var mantissa = String(parts[0])
        while mantissa.hasSuffix("0") { mantissa.removeLast() }
        if mantissa.hasSuffix(".") { mantissa.removeLast() }
        let power = Int(parts[1]) ?? 0
        return "\(mantissa)×10\(power < 0 ? "⁻" : "")\(superscript(abs(power)))".replacingOccurrences(of: "-", with: "−")
    }
    let digits = min(12, max(0, Options.figures - 1 - Int(floor(log10(abs(x))))))
    var s = String(format: "%.\(digits)f", x)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if s == "-0" { s = "0" }
    return s.replacingOccurrences(of: "-", with: "−")
}

// The nth Fibonacci number, from 0: 0, 1, 1, 2, 3, 5.
func fibonacci(_ v: Double) -> Double {
    guard v == v.rounded(), v >= 0, v <= 1476 else { return .nan }
    var (a, b) = (0.0, 1.0)
    for _ in 0..<Int(v) { (a, b) = (b, a + b) }
    return a
}

// How many of 1…n have no factor in common with it.
func totient(_ v: Double) -> Double {
    guard v == v.rounded(), v >= 1, v <= 1e12 else { return .nan }
    var n = Int(v), result = n, p = 2
    while p * p <= n {
        if n % p == 0 {
            while n % p == 0 { n /= p }
            result -= result / p
        }
        p += 1
    }
    if n > 1 { result -= result / n }
    return Double(result)
}

// The least prime greater than n.
func nextPrime(_ v: Double) -> Double {
    guard v == v.rounded(), v >= 0, v <= 1e12 else { return .nan }
    func isPrime(_ n: Int) -> Bool {
        guard n >= 2 else { return false }
        var p = 2
        while p * p <= n { if n % p == 0 { return false }; p += 1 }
        return true
    }
    var n = Int(v) + 1
    while !isPrime(n) { n += 1 }
    return Double(n)
}
