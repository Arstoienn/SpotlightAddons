import Foundation

// One equation in several letters that always stand together in it: 12 = 1.8 + 4v cos(θ) gives
// neither v nor θ, but it does give v cos(θ), the letters being taken as one unknown. They are
// the factors with a letter in them of a single product or quotient, and no letter may stand
// anywhere else: v cos(θ) + v = 3 has no such group.
struct Grouped {
    var equation: Equation   // with the group as its unknown
    var letters: [String]

    static func parse(_ input: String) -> Grouped? {
        guard var tokens = try? Parser.tokenize(input), tokens.filter({ $0 == .symbol("=") }).count == 1,
              !tokens.contains(where: { if case .marked = $0 { true } else { false } }) else { return nil }
        let ks = Parser.indices(tokens)
        var letters: [String] = []
        for token in tokens { if case .letter(let s) = token, !ks.contains(s), !letters.contains(s) { letters.append(s) } }
        // e is Euler's number, and g and c the constants they name, as they are with one unknown.
        let constants = Set(letters).intersection(Constants.all.keys)
        letters = letters.filter { $0 != "e" && !constants.contains($0) }
        guard letters.count >= 2 else { return nil }
        tokens = tokens.map { $0 == .letter("e") ? .constant(M_E) : $0 }
        var state = Parser.State(tokens: tokens, unknown: "", constants: constants, bound: letters)
        guard let left = try? state.expression(), state.take("="), let right = try? state.expression(), state.at == tokens.count,
              !left.hasSum, !right.hasSum else { return nil }

        // The letters on one side only, and there all within the one product.
        let lettered = Set(letters)
        guard mentions(left, lettered) != mentions(right, lettered),
              let (side, group) = taken(mentions(left, lettered) ? left : right, lettered) else { return nil }
        let name = typeset(group, "").plain.replacingOccurrences(of: "·(?=[a-z]+\\()", with: " ", options: .regularExpression)
        let equation = mentions(left, lettered) ? Equation(left: side, right: right, unknown: name)
                                                : Equation(left: left, right: side, unknown: name)
        // v cos(θ) = 2.55 is already its own answer.
        if case .unknown = equation.left, case .num = equation.right { return nil }
        if case .num = equation.left, case .unknown = equation.right { return nil }
        return Grouped(equation: equation, letters: letters)
    }

    // Whether a name is of several letters taken together, and not of one, θ or x_1.
    static func isGroup(_ name: String) -> Bool {
        name.replacingOccurrences(of: "_[A-Za-z0-9]+", with: "", options: .regularExpression).count > 1
    }

    // "v and θ cannot be found separately from one equation."
    var note: String {
        let named = letters.count == 2 ? letters.joined(separator: " and ")
                                       : letters.dropLast().joined(separator: ", ") + " and " + letters.last!
        return "\(named) cannot be found separately from one equation."
    }

    var solution: Solution? {
        guard var s = Solver.solve(equation) else { return nil }
        if s.approx == nil { s.approx = note }
        return s
    }

    var details: Details {
        var d = Solver.details(of: equation)
        if d.note == nil { d.note = note }
        return d
    }

    private static func mentions(_ e: Expr, _ letters: Set<String>) -> Bool {
        switch e {
        case .index(let k): return letters.contains(k)
        case .num, .unknown, .constant: return false
        case .neg(let a), .call(_, let a): return mentions(a, letters)
        case .op(_, let a, let b): return mentions(a, letters) || mentions(b, letters)
        case .apply(_, let args): return args.contains { mentions($0, letters) }
        case .sum(_, let from, let to, let body, _): return mentions(from, letters) || mentions(to, letters) || mentions(body, letters)
        }
    }

    // The side with the group made its unknown, and the group: found by going down to where the
    // letters part, which must be a product.
    private static func taken(_ e: Expr, _ letters: Set<String>) -> (Expr, group: Expr)? {
        switch e {
        case .op(let o, let a, let b):
            let inA = mentions(a, letters), inB = mentions(b, letters)
            if inA, !inB { return taken(a, letters).map { (.op(o, $0.0, b), $0.group) } }
            if inB, !inA { return taken(b, letters).map { (.op(o, a, $0.0), $0.group) } }
            return o == "*" || o == "/" ? product(e, letters) : nil
        case .neg(let a): return taken(a, letters).map { (.neg($0.0), $0.group) }
        case .call(let f, let a): return taken(a, letters).map { (.call(f, $0.0), $0.group) }
        case .apply(let f, var args):
            guard args.filter({ mentions($0, letters) }).count == 1, let i = args.firstIndex(where: { mentions($0, letters) }),
                  let (inner, group) = taken(args[i], letters) else { return nil }
            args[i] = inner
            return (.apply(f, args), group)
        default: return nil
        }
    }

    // 4·v·cos(θ) is 4 times the unknown v cos(θ); 6/(x·y) is 6 over the unknown x·y.
    private static func product(_ e: Expr, _ letters: Set<String>) -> (Expr, group: Expr)? {
        var factors: [(e: Expr, below: Bool)] = []
        var negative = false
        func flatten(_ e: Expr, _ below: Bool) {
            switch e {
            case .op("*", let a, let b): flatten(a, below); flatten(b, below)
            case .op("/", let a, let b): flatten(a, below); flatten(b, !below)
            case .neg(let a): negative.toggle(); flatten(a, below)
            default: factors.append((e, below))
            }
        }
        flatten(e, false)
        func multiplied(_ es: [Expr]) -> Expr? { es.isEmpty ? nil : es.dropFirst().reduce(es[0]) { .op("*", $0, $1) } }
        func part(_ lettered: Bool, below: Bool) -> Expr? {
            multiplied(factors.filter { mentions($0.e, letters) == lettered && $0.below == below }.map(\.e))
        }
        let top = part(true, below: false), bottom = part(true, below: true)
        guard let group = top.map({ t in bottom.map { .op("/", t, $0) } ?? t }) ?? bottom else { return nil }
        var side: Expr
        if top != nil { side = part(false, below: false).map { .op("*", $0, .unknown) } ?? .unknown }
        else { side = .op("/", part(false, below: false) ?? .num(1), .unknown) }
        if let under = part(false, below: true) { side = .op("/", side, under) }
        return (negative ? .neg(side) : side, group)
    }
}
