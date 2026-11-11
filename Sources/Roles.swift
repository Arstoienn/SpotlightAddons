import Foundation

// The part each letter plays in what was typed, decided in one place by one set of rules:
//   e is Euler's number, unless it is the only letter;
//   a letter given a number after the question, n = 1/2, is given;
//   a letter naming a constant of physics, g or c, is that constant where other letters are left;
//   in several equations, x, y and z are the unknowns, and the other letters stand for numbers;
//   in one equation, the one letter left is the unknown, and with several, it is undecided here;
//   with a derivative written in it, dy/dx, y is the unknown function and x its variable.
struct Roles {
    var letters: [String]         // every letter, in the order it is met
    var unknowns: [String]
    var parameters: [String]      // letters standing for numbers that were not given
    var constants: [String]       // g, c and the like, taken for their values
    var given: [String]
    var euler: Bool               // e is Euler's number in it
    var tree: [Statement]         // each part of the input, read once with no letter given a part

    struct Statement {
        var left: Expr
        var right: Expr?          // nil for an expression with no = in it
    }

    // The letters of a run of tokens, in order, the k of a sum left out.
    static func letters(_ tokens: [Parser.Token]) -> [String] {
        let indices = Parser.indices(tokens)
        var out: [String] = []
        for token in tokens {
            if case .letter(let s) = token, !indices.contains(s), !out.contains(s) { out.append(s) }
            if case .marked(let s) = token, !out.contains(s) { out.append(s) }
        }
        return out
    }

    // e is Euler's number unless it is the only letter, or is given a value or asked for.
    static func isEuler(_ letters: [String], given: Set<String> = []) -> Bool {
        letters.contains("e") && letters.count > 1 && !given.contains("e")
    }

    // The letters among these naming a constant of physics, and not given a value of their own.
    static func constants(among letters: Set<String>, given: Set<String> = []) -> Set<String> {
        letters.intersection(Constants.all.keys).subtracting(given)
    }

    // A part read with every letter standing for itself.
    static func statement(_ text: String) -> Statement? {
        guard let tokens = try? Parser.tokenize(text), tokens.filter({ $0 == .symbol("=") }).count <= 1,
              !tokens.contains(where: { if case .marked = $0 { true } else { false } }) else { return nil }
        var state = Parser.State(tokens: tokens, unknown: "", bound: letters(tokens))
        guard let left = try? state.expression() else { return nil }
        var right: Expr?
        if state.take("=") { guard let r = try? state.expression() else { return nil }; right = r }
        guard state.at == tokens.count else { return nil }
        return Statement(left: left, right: right)
    }

    static func of(_ input: String) -> Roles? {
        let parts = LinearSystem.parts(input)
        var all: [String] = [], given: [String] = [], tree: [Statement] = [], equations = 0
        for (index, part) in parts.enumerated() {
            guard let tokens = try? Parser.tokenize(part) else { return nil }
            let these = letters(tokens)
            // n = 1/2, θ = 30°: a letter given a number, after the question; h = 0.5g·3² by itself is the question.
            if index > 0, tokens.count >= 3, case .letter(let name) = tokens[0], tokens[1] == .symbol("="),
               (try? Parser.constant(String(part.split(separator: "=", maxSplits: 1)[1]))) != nil {
                if !given.contains(name) { given.append(name) }
                continue
            }
            for s in these where !all.contains(s) { all.append(s) }
            if tokens.contains(.symbol("=")) { equations += 1 }
            if let statement = statement(part) { tree.append(statement) }
        }
        let givenSet = Set(given)
        let euler = isEuler(all, given: givenSet)
        let free = all.filter { !(euler && $0 == "e") && !givenSet.contains($0) }
        let constants = free.count > 1 ? constants(among: Set(free), given: givenSet) : []
        var rest = free.filter { !constants.contains($0) }
        var unknowns: [String] = []
        if Differential.mentionsDerivative(input) {
            // dy/dx: y the unknown function, x its variable, and d no letter at all.
            unknowns = rest.contains("y") ? ["y"] : []
            rest.removeAll { ["d", "x"].contains($0) }
        } else if equations >= 2 {
            unknowns = ["x", "y", "z"].filter(rest.contains)
        } else if equations == 1, rest.count == 1 {
            unknowns = rest
        }
        rest.removeAll { unknowns.contains($0) }
        return Roles(letters: all, unknowns: unknowns, parameters: equations > 0 ? rest : [], constants: constants.sorted(),
                     given: given, euler: euler, tree: tree)
    }
}

extension Expr {
    // The tree with the parts given: the unknown as the unknown, a constant of physics as its value,
    // and e as Euler's number where it is not the unknown. The k of a sum is left alone in its body.
    func lowered(unknown: String, constants: Set<String>, euler: Bool) -> Expr {
        switch self {
        case .index(let name):
            if name == unknown { return .unknown }
            if constants.contains(name), let value = Constants.all[name] { return .constant(name, value.value) }
            if name == "e", euler { return .num(M_E) }
            return self
        case .num, .unknown, .constant: return self
        case .neg(let a): return .neg(a.lowered(unknown: unknown, constants: constants, euler: euler))
        case .op(let o, let a, let b): return .op(o, a.lowered(unknown: unknown, constants: constants, euler: euler), b.lowered(unknown: unknown, constants: constants, euler: euler))
        case .call(let f, let a): return .call(f, a.lowered(unknown: unknown, constants: constants, euler: euler))
        case .apply(let f, let args): return .apply(f, args.map { $0.lowered(unknown: unknown, constants: constants, euler: euler) })
        case .sum(let k, let from, let to, let body, let product):
            return .sum(k, from: from.lowered(unknown: unknown, constants: constants, euler: euler), to: to.lowered(unknown: unknown, constants: constants, euler: euler),
                        k == unknown ? body : body.lowered(unknown: unknown, constants: constants.subtracting([k]), euler: euler && k != "e"), product: product)
        }
    }
}
