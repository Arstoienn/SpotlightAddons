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
        // A digest is of the text exactly as typed. One asked for as a number, inside a sum, is
        // written in as that number first; one in hexadecimal inside a sum is nothing to work out.
        if let hash = Hash.parse(typed) { return hash.solution }
        guard let typed = Hash.numbers(in: typed) else { return nil }
        let input = Latex.plain(typed)
        if LinearSystem.parts(input).count >= 2 { return LinearSystem.parse(input)?.solution ?? NonlinearSystem.parse(input)?.solution }
        if let number = NumberFacts.parse(input) { return number.solution }
        if let comparison = Comparison.parse(input) { return comparison.solution }
        if let evaluation = Evaluation.parse(input, hadLatex: typed.contains("\\")) { return evaluation.solution }
        guard let equation = try? Parser.parse(input) else { return nil }
        // "x = 5" is already its own answer.
        if case .unknown = equation.left, case .num = equation.right { return nil }
        if case .num = equation.left, case .unknown = equation.right { return nil }
        let name = equation.unknown
        // With a physical constant in it the answer is a decimal, the constant being only a few
        // figures itself, and the card says what was taken for it when it has the room.
        let constants = equation.constants
        var solution: Solution?
        if let left = poly(equation.left), let right = poly(equation.right) {
            solution = solvePolynomial(trim(sub(left, right)), name, exact: constants.isEmpty)
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
            default: return pow(l, r)
            }
        case .call(let f, let e): return Functions.apply(f, e.eval(x, indices))
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
        case .sum(let name, let from, let to, let body, let product):
            return .sum(name, from: from.setting(k, to: v), to: to.setting(k, to: v),
                        name == k ? body : body.setting(k, to: v), product: product)
        }
    }

    var hasUnknown: Bool {
        switch self {
        case .unknown: return true
        case .num, .index, .constant: return false
        case .neg(let a), .call(_, let a): return a.hasUnknown
        case .op(_, let a, let b): return a.hasUnknown || b.hasUnknown
        case .sum(_, let from, let to, let body, _): return from.hasUnknown || to.hasUnknown || body.hasUnknown
        }
    }

    var hasSum: Bool {
        switch self {
        case .sum: return true
        case .num, .unknown, .index, .constant: return false
        case .neg(let a), .call(_, let a): return a.hasSum
        case .op(_, let a, let b): return a.hasSum || b.hasSum
        }
    }

    // The physical constants in it, each once, in the order they are met.
    var constants: [String] {
        switch self {
        case .constant(let name, _): return [name]
        case .num, .unknown, .index: return []
        case .neg(let a), .call(_, let a): return a.constants
        case .op(_, let a, let b): return unique(a.constants + b.constants)
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
    return sum.isFinite && abs(sum) <= 1e-12 * max(abs(a), abs(b)) ? 0 : sum
}

enum Functions {
    static let names = ["sqrt", "asin", "acos", "atan", "sin", "cos", "tan", "exp", "abs", "log", "ln"]

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

    // A sine whose angle has a degree mark anywhere in it works in degrees throughout.
    static func call(_ f: String, _ argument: Expr) -> Expr {
        guard functions.contains(f) else { return .call(f, argument) }
        return .call(saysDegrees(argument) ? f + "°" : f, unmarked(argument))
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

    private static func saysDegrees(_ e: Expr) -> Bool {
        switch e {
        case .num, .unknown, .index, .constant: return false
        case .neg(let a): return saysDegrees(a)
        case .op(_, let a, let b): return saysDegrees(a) || saysDegrees(b)
        case .call(let f, let a): return f == "deg" || saysDegrees(a)
        case .sum(_, let from, let to, let body, _): return saysDegrees(from) || saysDegrees(to) || saysDegrees(body)
        }
    }

    private static func unmarked(_ e: Expr) -> Expr {
        switch e {
        case .num, .unknown, .index, .constant, .sum: return e
        case .neg(let a): return .neg(unmarked(a))
        case .op(let o, let a, let b): return .op(o, unmarked(a), unmarked(b))
        case .call(let f, let a): return f == "deg" || f == "rad" ? unmarked(a) : .call(f, unmarked(a))
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

// The constants of the IB physics data booklet whose symbols are typed as they stand, with the
// values it gives. A letter is one of these only when the equation has another letter to be its
// unknown: 2c = 6 is still solved for c, and x = 2g is 19.6.
enum Constants {
    static let all: [String: (value: Double, text: String)] = [
        "g": (9.8, "9.8 m s⁻²"),
        "G": (6.67e-11, "6.67×10⁻¹¹ N m² kg⁻²"),
        "c": (3.00e8, "3.00×10⁸ m s⁻¹"),
    ]

    // "g = 9.8 m s⁻², c = 3.00×10⁸ m s⁻¹", for the card and the working to say what was used.
    static func values(_ names: [String]) -> String {
        names.compactMap { name in all[name].map { "\(name) = \($0.text)" } }.joined(separator: ", ")
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
            ("×", "*"), ("·", "*"), ("÷", "/"), ("−", "-"), ("²", "^2"), ("³", "^3"), ("π", "pi"), ("√", "sqrt"),
        ]
        // Capitals are kept: G is not g, and E is a letter where e is Euler's number.
        var s = input
        for (from, to) in replacements { s = s.replacingOccurrences(of: from, with: to) }

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
                tokens += try splitLetters(String(s[i..<j]))
                i = try attachSubscript(&tokens, s, j)
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
            } else if "+-*/^()=,!".contains(c) {
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
        case .number, .letter, .constant, .marked, .symbol(")"), .symbol("!"), .symbol("°"), .symbol("㎭"): true
        default: false
        }
    }

    // "sinx" is sin x and "2nx" would be n times x: known names first, then single letters.
    static func splitLetters(_ run: String) throws -> [Token] {
        var out: [Token] = []
        var rest = Substring(run)
        while !rest.isEmpty {
            if let f = (["sum", "prod"] + Functions.names).first(where: { rest.hasPrefix($0) }) {
                out.append(.function(f))
                rest = rest.dropFirst(f.count)
            } else if rest.hasPrefix("pi") {
                out.append(.constant(.pi))
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("deg") {
                out.append(.symbol("°"))
                rest = rest.dropFirst(3)
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
        return out
    }

    struct State {
        let tokens: [Token]
        let unknown: String
        var constants: Set<String> = []   // the letters read as physical constants
        var at = 0
        var bound: [String] = []   // the k of each sum being read

        var next: Token? { at < tokens.count ? tokens[at] : nil }

        mutating func take(_ c: Character) -> Bool {
            if next == .symbol(c) { at += 1; return true }
            return false
        }

        mutating func expression() throws -> Expr {
            var e = try term()
            while true {
                if take("+") { e = .op("+", e, try term()) }
                else if take("-") { e = .op("-", e, try term()) }
                else { return e }
            }
        }

        // Juxtaposition multiplies, as on paper: 2n, 2(n+1), (x+1)(x-1), 3sin x.
        mutating func term() throws -> Expr {
            var e = try unary()
            while true {
                if take("*") { e = .op("*", e, try unary()) }
                else if take("/") { e = .op("/", e, try unary()) }
                else if startsOperand { e = .op("*", e, try power()) }
                else { return e }
            }
        }

        var startsOperand: Bool {
            switch next {
            case .number, .letter, .function, .constant, .marked, .symbol("("): true
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
            var base = try primary()
            // 35° and x deg say degrees, to the sine they are inside; x rad says radians, as it
            // would have been anyway.
            while true {
                if take("!") { base = .call("fact", base) }
                else if take("°") { base = Angle.marked(base, degrees: true) }
                else if take("㎭") { base = Angle.marked(base, degrees: false) }
                else { break }
            }
            return take("^") ? .op("^", base, try unary()) : base
        }

        mutating func primary() throws -> Expr {
            guard let t = next else { throw Failure() }
            at += 1
            switch t {
            case .number(let v), .constant(let v): return .num(v)
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
            // sin(x)^2 is (sin x)², as written on paper; sin x^2 is sin(x²).
            case .function(let f):
                if take("(") {
                    let e = try expression()
                    guard take(")") else { throw Failure() }
                    return Angle.call(f, e)
                }
                return Angle.call(f, try power())
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
        let re = -Double(b) / Double(2 * a), im = Double(-d).squareRoot() / Double(2 * abs(a))
        let imText = (im == 1 ? "" : decimal(im)) + "i"
        return Solution(exact: "No real solutions", approx: "Complex solutions: \(name) ≈ " + (re == 0 ? "±\(imText)" : "\(decimal(re)) ± \(imText)"))
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

    func accept(_ x: Double) {
        let y = f(x)
        guard y.isFinite, abs(y) <= 1e-7 * max(1, abs(eq.left.eval(x))) else { return }
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
            if y0.isFinite, abs(y0) < prevAbs, y1.isFinite, abs(y1) > abs(y0), abs(y0) < 1e-2 { accept(newton(f, x0)) }
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
        for _ in 0..<(real ? 50 : 0) {
            let (y, slope) = value(x)
            guard slope.isFinite, slope != 0 else { break }
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
    guard let shown = Double(String(format: "%.5e", x)) else { return false }
    return abs(shown - x) <= 1e-12 * size
}

// Six significant figures, with a real minus sign: written out where that can be read, and as
// 6.67×10⁻¹¹ where it cannot, which is the very large, the very small, and round numbers from ten
// million up (3×10⁸, but 12345678).
func decimal(_ x: Double) -> String {
    if x == 0 { return "0" }
    guard x.isFinite else { return String(format: "%.6g", x).replacingOccurrences(of: "-", with: "−") }
    let size = abs(x)
    let round = size >= 1e7 && size < 1e12 && x == x.rounded() && String(Int(size)).reversed().drop(while: { $0 == "0" }).count <= 4
    if size >= 1e12 || size < 1e-6 || round {
        let parts = String(format: "%.5e", x).split(separator: "e")
        var mantissa = String(parts[0])
        while mantissa.hasSuffix("0") { mantissa.removeLast() }
        if mantissa.hasSuffix(".") { mantissa.removeLast() }
        let power = Int(parts[1]) ?? 0
        return "\(mantissa)×10\(power < 0 ? "⁻" : "")\(superscript(abs(power)))".replacingOccurrences(of: "-", with: "−")
    }
    let digits = min(12, max(0, 5 - Int(floor(log10(abs(x))))))
    var s = String(format: "%.\(digits)f", x)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if s == "-0" { s = "0" }
    return s.replacingOccurrences(of: "-", with: "−")
}
