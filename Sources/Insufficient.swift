import Foundation

// Equations with more unknowns than they can determine: mgh = ½mv² gives neither h nor v until
// one of them is given. The card says so, and which values are wanted, rather than nothing.
struct Insufficient {
    var unknowns: [String]        // h, v: the letters with no value, m having divided out
    var required: Int             // how many of them must be given
    var cancelled: [String]
    var header: Math
    var reduced: Math?            // gh = ½v², after m has divided out
    var expressed: [(letter: String, result: Math)] = []   // h = v²/(2g), v = ±√(2gh): each in terms of the rest

    static func parse(_ input: String) -> Insufficient? {
        let parts = LinearSystem.parts(input)
        guard (1...6).contains(parts.count), input.contains(where: \.isNumber) else { return nil }
        var given: Set<String> = []
        var known: [(name: String, value: Double)] = []
        var sources: [String] = []
        var equations: [(left: Expr, right: Expr?)] = []
        var letters: [String] = []
        var texts: [[Parser.Token]] = []
        for part in parts {
            guard let tokens = try? Parser.tokenize(part), tokens.filter({ $0 == .symbol("=") }).count <= 1,
                  !tokens.contains(where: { if case .marked = $0 { true } else { false } }) else { return nil }
            // u = 2 gives u; it is no equation to be solved.
            if tokens.count >= 3, case .letter(let name) = tokens[0], tokens[1] == .symbol("="),
               let value = (try? Parser.constant(part.split(separator: "=", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)))?.eval(0), value.isFinite {
                given.insert(name)
                known.append((name, value))
                continue
            }
            texts.append(tokens)
            sources.append(part)
            let ks = Parser.indices(tokens)
            for token in tokens { if case .letter(let s) = token, !ks.contains(s), !letters.contains(s) { letters.append(s) } }
        }
        // An expression on its own, with nothing given, is no question of this kind: x + y.
        guard !texts.isEmpty, texts.contains(where: { $0.contains(.symbol("=")) }) || !given.isEmpty else { return nil }
        // e is Euler's number, and g and c the constants they name, unless they are given.
        let constants = Roles.constants(among: Set(letters), given: given)   // the shared rules (Roles.swift)
        var unknowns = letters.filter { $0 != "e" && !constants.contains($0) && !given.contains($0) }
        guard !unknowns.isEmpty, unknowns.count <= 6 else { return nil }
        for tokens in texts {
            let tokens = tokens.map { $0 == .letter("e") && !unknowns.contains("e") ? .constant(M_E) : $0 }
            var state = Parser.State(tokens: tokens, unknown: "", constants: constants, bound: letters.filter { !constants.contains($0) })
            guard let left = try? state.expression() else { return nil }
            var right: Expr?
            if state.take("=") { guard let r = try? state.expression() else { return nil }; right = r }
            guard state.at == tokens.count else { return nil }
            equations.append((left, right))
        }
        let header = Math.row(equations.enumerated().flatMap { i, e in
            (i == 0 ? [] : [t(",   ")]) + [typeset(e.left, "")] + (e.right.map { [t(" = "), typeset($0, "")] } ?? [])
        })

        // An equation with one unknown left settles it, and that one is then known to the rest:
        // in 5.05 = 1.6f, f = Nμ, f is found from the first, and N or μ is what is wanted.
        var open = equations.indices.filter { equations[$0].right != nil }
        var found: Set<String> = []
        var worked = true   // each one settled was found as one number, and can be written in
        func left(_ e: (left: Expr, right: Expr?)) -> [String] {
            unknowns.filter { name in !found.contains(name) && (Grouped.mentions(e.left, [name]) || e.right.map { Grouped.mentions($0, [name]) } == true) }
        }
        while let i = open.firstIndex(where: { left(equations[$0]).count == 1 }) {
            let name = left(equations[open[i]])[0]
            if let text = Given.write(known, [:], into: sources[open[i]]), case let values = Solver.values(text), values.count == 1 {
                known.append((name, values[0]))
            } else {
                worked = false
            }
            found.insert(name)
            open.remove(at: i)
        }
        unknowns = unknowns.filter { !found.contains($0) }

        // A letter that is a factor of both sides of the one equation left divides out, as m does.
        var cancelled: [String] = []
        var reduced: Math?
        if open.count == 1, var left = open.first.map({ equations[$0].left }), var right = open.first.flatMap({ equations[$0].right }) {
            for name in unknowns {
                guard let l = Grouped.without(left, name), let r = Grouped.without(right, name),
                      !Grouped.mentions(l, [name]), !Grouped.mentions(r, [name]) else { continue }
                (left, right) = (l, r)
                cancelled.append(name)
            }
            if !cancelled.isEmpty { reduced = row(typeset(left, ""), t(" = "), typeset(right, "")) }
            unknowns = unknowns.filter { !cancelled.contains($0) && (Grouped.mentions(left, [$0]) || Grouped.mentions(right, [$0])) }
        }
        // Each equation settles one unknown; an expression settles none, and wants all its letters.
        let required = unknowns.count - open.count
        guard required >= 1 else { return nil }
        // With one equation left, each unknown in terms of the others, what is known written in:
        // h = v²/(2g), and in 5.05 = 1.6f, f = Nμ, N = 101/(32μ).
        var expressed: [(letter: String, result: Math)] = []
        if open.count == 1, worked, let text = Given.write(known, [:], into: sources[open[0]]) {
            expressed = unknowns.compactMap { u in Rearrangement.parse(text, for: u).map { (u, $0.result) } }
        }
        return Insufficient(unknowns: unknowns, required: required, cancelled: cancelled, header: header, reduced: reduced, expressed: expressed)
    }

    // "A value is required for h or v", "Values are required for two of a, b and c".
    var wanted: String {
        func list(_ names: [String], _ last: String) -> String {
            names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " \(last) " + names.last!
        }
        let numbers = ["one", "two", "three", "four", "five", "six"]
        if required == unknowns.count {
            return required == 1 ? "A value is required for \(unknowns[0])." : "Values are required for \(list(unknowns, "and"))."
        }
        if required == 1 {
            return unknowns.count == 2 ? "A value is required for \(list(unknowns, "or"))."
                                       : "A value is required for one of \(list(unknowns, "or"))."
        }
        return "Values are required for \(numbers[required - 1]) of \(list(unknowns, "and"))."
    }

    var solution: Solution { Solution(exact: "Insufficient information", approx: wanted) }

    var details: Details {
        var steps: [Step] = []
        if let reduced { steps.append(Step(label: "Dividing both sides by " + cancelled.joined(), math: reduced)) }
        let words = ["no", "one", "two", "three", "four", "five", "six"]
        let k = unknowns.count, n = k - required
        let note = k == 1 ? "There is one unknown and no equation to determine it."
                 : n == 0 ? "There are \(words[k]) unknowns and no equation to determine them."
                 : "There are \(words[k]) unknowns but only \(words[n]) equation\(n == 1 ? "" : "s") to determine them; each equation determines at most one unknown."
        steps.append(Step(label: "Identifying the unknowns", math: t(unknowns.joined(separator: ", ")), note: note))
        for (letter, result) in expressed {
            let others = unknowns.filter { $0 != letter }
            let named = others.count == 1 ? others[0] : others.dropLast().joined(separator: ", ") + " and " + others.last!
            steps.append(Step(label: "Expressing \(letter) in terms of \(named)", math: result))
        }
        return Details(name: unknowns.joined(separator: ", "), equation: header, steps: steps,
                       solutions: expressed.isEmpty ? [t("Insufficient information")] : expressed.map(\.result), note: wanted,
                       f: { _ in .nan }, roots: [])
    }
}
