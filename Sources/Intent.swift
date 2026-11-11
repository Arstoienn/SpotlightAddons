import Foundation

// What is being asked, read from the input once, before anything is worked out: to solve an
// equation, to give a Taylor polynomial, to solve a differential equation, to work something out,
// and so on, with what it is asked of. The pipeline then answers it (Pipeline.swift).
enum MathIntent {
    case command(Command)
    case astronomy(Astronomy)
    case place(Location)
    case money(Conversion)
    case digest(Hash)
    case colour(Colour)
    case circuit(Circuit)
    case sequence(Sequence)
    case severalAnswers(count: Int, named: String)   // ans, when the last question had several
    case matrix(MatrixValue)
    case differentialEquation(Differential)
    case taylor(Taylor)
    case euler(Euler)
    case angleIdentity(AngleIdentity)
    case namedOperation(Algebra)                     // expand, factor, derivative, integrate, limit
    case solveInRange(Domain)
    case givenValues(Given)
    case linearSystem(LinearSystem)
    case nonlinearSystem(NonlinearSystem)
    case letterSystem(LetterSystem)
    case insufficient(Insufficient)
    case conversion(Conversion)
    case complex(ComplexValue)
    case numberFacts(NumberFacts)
    case logic(Logic)
    case comparison(Comparison)
    case inequality(Inequality)
    case inequalities(InequalitySet)
    case relation(Relation)                          // y = x², f(x) = sin x, x² + y² = 5: a curve, drawn
    case proof(Proof)                                // p² − 8q − 11 = 0 has no integer solutions; n³ − n is divisible by 6; √2 is irrational
    case conditioned(Conditioned)                    // C(11,4)x⁷k⁴, 330k⁴ = 1320: the equation solved, its value put into the expression
    case evaluate(Evaluation, Solution, asTyped: String)
    case factorise(Algebra)
    case simplify(Simplification)
    case trigIdentity(TrigSimplification)
    case rearrange(Rearrangement)
    case grouped(Grouped, Solution)
    case solveEquation(Equation, Solution)

    // The card's sign, an SF Symbol, saying at a glance what kind of answer it is: ±/ for something
    // worked out, x√ for an equation solved, < for an inequality, ƒ(x) for calculus on a function,
    // ( ) for an expression tidied or factorised, ✓ or ✗ for a statement judged, and so on. A path
    // and a command have theirs from the card itself (a folder or a page, and a terminal).
    var symbol: String {
        switch self {
        case .command: return "terminal"
        case .astronomy: return "moon.stars"
        case .place(let place): return place.isFolder ? "folder" : "doc"
        case .money: return "banknote"
        case .digest: return "lock"
        case .colour: return "paintpalette"
        case .circuit: return "cpu"
        case .relation: return "chart.xyaxis.line"
        case .conditioned: return "x.squareroot"
        case .proof: return "checkmark.seal"
        case .sequence: return "list.number"
        case .severalAnswers: return "list.bullet"
        case .matrix: return "square.grid.3x3"
        case .differentialEquation, .taylor, .euler: return "function"
        case .angleIdentity: return "x.squareroot"
        case .namedOperation(let algebra): return algebra.calculus ? "function" : "parentheses"
        case .solveInRange, .givenValues, .linearSystem, .nonlinearSystem, .letterSystem, .insufficient, .rearrange, .grouped, .solveEquation:
            return "x.squareroot"
        case .conversion: return "arrow.left.arrow.right"
        // The calculator's key, ±/, and not =: beside an answer that begins = 2, it would read == 2.
        case .complex, .evaluate: return "plus.forwardslash.minus"
        case .numberFacts: return "number"
        case .logic(let logic): return logic.holds ? "checkmark.circle" : "xmark.circle"
        case .comparison(let comparison): return comparison.holds ? "checkmark.circle" : "xmark.circle"
        case .inequality, .inequalities: return "lessthan"
        case .factorise, .simplify, .trigIdentity: return "parentheses"
        }
    }

    // In words, for the working and the tests: "Solving an equation".
    var name: String {
        switch self {
        case .command: return "Running a command"
        case .astronomy: return "Working out an astronomical quantity"
        case .place: return "Naming a place"
        case .money: return "Converting money"
        case .digest: return "Taking a digest"
        case .colour: return "Working with a colour"
        case .circuit: return "Working through a logic circuit"
        case .relation: return "Drawing a graph"
        case .conditioned: return "Solving for a letter in an expression"
        case .proof: return "Proving a statement"
        case .sequence: return "Finding a sequence"
        case .severalAnswers: return "Choosing an answer"
        case .matrix: return "Working with matrices"
        case .differentialEquation: return "Solving a differential equation"
        case .taylor: return "Finding a Taylor polynomial"
        case .euler: return "Applying Euler's method"
        case .angleIdentity: return "Proving an identity"
        case .namedOperation: return "Carrying out a named operation"
        case .solveInRange: return "Solving in a range"
        case .givenValues: return "Writing in the values given"
        case .linearSystem, .nonlinearSystem: return "Solving simultaneous equations"
        case .letterSystem: return "Solving simultaneous equations in letters"
        case .insufficient: return "Finding what is wanting"
        case .conversion: return "Converting units"
        case .complex: return "Working with complex numbers"
        case .numberFacts: return "Describing a number"
        case .logic, .comparison: return "Judging a statement"
        case .inequality, .inequalities: return "Solving an inequality"
        case .evaluate: return "Evaluating"
        case .factorise: return "Factorising"
        case .simplify: return "Simplifying"
        case .trigIdentity: return "Applying a trigonometric identity"
        case .rearrange: return "Rearranging a formula"
        case .grouped: return "Solving for letters together"
        case .solveEquation: return "Solving an equation"
        }
    }
}

// The input as it was read: what is asked, the text the rest of the solver reads, the parts each
// letter plays in it, and anything the person typing should know about how it was taken.
struct Reading {
    var intent: MathIntent
    var input: String
    var roles: Roles?
    var notes: [String] = []
    var judged: [String] = []   // statements in brackets taken as 1 or 0: (0 = 0) is True, taken as 1
}

enum Analyzer {
    // How deep the brackets go, of any kind: (((1))) is 3.
    static func nesting(_ text: String) -> Int {
        var depth = 0, deepest = 0
        for c in text {
            if "([{".contains(c) { depth += 1; deepest = max(deepest, depth) } else if ")]}".contains(c) { depth -= 1 }
        }
        return deepest
    }

    // Read the input, and say what is asked of it; nil for what is no question.
    static func read(_ typed: String) -> Reading? {
        // Past anything typed into Spotlight, a thousand characters or brackets sixty deep, there is
        // no card: a sum of thousands of terms, or roots nested hundreds deep, would take seconds to
        // read, work out, write out and draw, or run out of room doing it.
        guard typed.count <= (Astronomy.marked(typed) ? 32000 : 1000), Analyzer.nesting(typed) <= 60 else { return nil }
        // A line for Terminal is read before anything else, and kept exactly as typed: > 2+2 is a
        // command, not 4, and ans and clip in it are left as they are.
        if let command = Command.parse(typed) { return Reading(intent: .command(command), input: typed) }
        // After @, astronomy, and nothing else: @ 2+2 is no sum, and a call half typed is no
        // question yet, while completion offers what fits (Completion.swift).
        if Astronomy.marked(typed) { return Astronomy.parse(typed).map { Reading(intent: .astronomy($0), input: typed) } }
        if let place = Location.parse(typed) { return Reading(intent: .place(place), input: typed) }
        // Money is read as typed: a $ before the amount is no mark of mathematics.
        if let money = Currency.conversion(typed) { return Reading(intent: .money(money), input: typed) }
        // A digest is of the text exactly as typed.
        if let hash = Hash.parse(typed) { return Reading(intent: .digest(hash), input: typed) }
        // A colour, #FF5733 or rgb(255, 87, 51), is read as typed: # is no mark of mathematics either.
        if let colour = Colour.parse(typed) { return Reading(intent: .colour(colour), input: typed) }
        // s0 = a0 xor b0, c1 = a0 and b0, or the same in LaTeX: a logic circuit, read before any of it is taken as arithmetic.
        if let circuit = Circuit.parse(typed) { return Reading(intent: .circuit(circuit), input: typed) }
        // A statement about whole numbers to prove, in words: read before the words turn it away as prose.
        if let proof = Proof.parse(typed) { return Reading(intent: .proof(proof), input: typed) }
        let asTyped = typed   // before it is tidied: lcm(4,6) is not bracketed as it was written
        guard let tidied = Hash.numbers(in: typed).map(Prose.tidy), !Prose.reads(tidied) else { return nil }
        // (0 = 0) = 0: a statement in brackets used as a number is 1 or 0, and the card says which.
        let (typed, judged) = Iverson.substituted(Ordering.questionFirst(tidied))
        // u_1 = 12, u_5 = 29, u_10 = ? asks for the tenth term, and is no "x = ?" after a formula.
        if let sequence = Sequence.parse(Latex.plain(typed)) { return Reading(intent: .sequence(sequence), input: typed) }
        if Sequence.tooFarAlong(Latex.plain(typed)) { return nil }
        // "x=?" after a formula asks for it to be turned round to give x.
        // Matrices given by name, with the question among them, A = […], B = […], A + B = ?, are
        // written in first: the = ? there asks for A + B, and not for B as in F = ma, a = ?.
        let plain = Latex.plain(typed), named = Solver.rewritten(plain)
        let asked = named.contains("[") && named != plain ? nil : Rearrangement.asked(plain)
        let input = asked.map { Solver.rewritten($0.equation) } ?? named
        let roles = Roles.of(input)
        let notes = Notes.of(input, roles: roles)
        func reading(_ intent: MathIntent) -> Reading { Reading(intent: intent, input: input, roles: roles, notes: judged + notes, judged: judged) }

        // ans, when the question before had several answers, is no one of them.
        if Memory.answers.count > 1, input.range(of: "(?<![A-Za-z])[Aa]ns(?![A-Za-z0-9_])", options: .regularExpression) != nil {
            let named = Memory.answers.prefix(4).enumerated().map { "ans\($0 + 1) = \(decimal($1))" }.joined(separator: ", ")
            return reading(.severalAnswers(count: Memory.answers.count, named: named))
        }
        if let matrix = MatrixValue.parse(input) { return reading(.matrix(matrix)) }
        // A derivative written in it, dy/dx or y′: a differential equation, solved or not shown at all.
        if Differential.mentionsDerivative(input), input.contains("=") { return Differential.parse(input).map { reading(.differentialEquation($0)) } }
        // T_5(x), f(x) = …: x the variable of the polynomial, and any other letter in f one it holds.
        // euler(x+y, 0, 1, 0.1, 3): Euler's method, step by step.
        if let euler = Euler.parse(input) { return reading(.euler(euler)) }
        // sin(A + B) = sin A cos B + cos A sin B: an identity in two angles or more, proved.
        if let identity = AngleIdentity.prove(input) { return reading(.angleIdentity(identity)) }
        if let taylor = Taylor.parse(input) {
            var r = reading(.taylor(taylor))
            r.roles?.unknowns = [taylor.name]
            r.roles?.parameters = taylor.series.letters
            return r
        }
        if let algebra = Algebra.parse(input) { return reading(.namedOperation(algebra)) }
        if let domain = Domain.parse(input) { return reading(.solveInRange(domain)) }
        // Several statements: values given to a formula or an expression, a system, or too few
        // equations for the unknowns, in that order.
        if LinearSystem.parts(input).count >= 2 {
            if let given = Given.parse(input) { return reading(.givenValues(given)) }
            if let system = LinearSystem.parse(input) { return reading(.linearSystem(system)) }
            if let system = NonlinearSystem.parse(input) { return reading(.nonlinearSystem(system)) }
            // Linear in x, y (and z) with letters for coefficients: solved in those letters.
            if let lettered = LetterSystem.parse(input) { return reading(.letterSystem(lettered)) }
            // An expression with the one equation that settles a letter in it.
            if let conditioned = Conditioned.parse(input) { return reading(.conditioned(conditioned)) }
            return Insufficient.parse(input).map { reading(.insufficient($0)) }
        }
        // One equation in x and y alone, or f(x) = …: a curve to draw, with nothing to solve for,
        // unless a letter is asked for, as in x + y = 3, y = ?, which is the formula turned round.
        if asked == nil, let relation = Relation.parse(input) { return reading(.relation(relation)) }
        if let conversion = Conversion.parse(input) { return reading(.conversion(conversion)) }
        if let complex = ComplexValue.parse(input) { return reading(.complex(complex)) }
        // A number by itself is said something of, and is nothing to copy or to keep as ans.
        if let number = NumberFacts.parse(input) { return reading(.numberFacts(number)) }
        if let logic = Logic.parse(input) { return reading(.logic(logic)) }
        if let comparison = Comparison.parse(input) { return reading(.comparison(comparison)) }
        if let inequality = Inequality.parse(input) { return reading(.inequality(inequality)) }
        if let inequalities = InequalitySet.parse(input) { return reading(.inequalities(inequalities)) }
        if let evaluation = Evaluation.parse(input, hadLatex: typed.contains("\\")) {
            return evaluation.solution.map { reading(.evaluate(evaluation, $0, asTyped: asTyped)) }
        }
        // cost = 90 gives a name a number, and there is nothing to work out: it is not cos t = 90.
        if Evaluation.namesNumber(input) { return nil }
        // A polynomial in one letter that factorises, wholly, before it is only tidied.
        if !input.contains("="), let algebra = factorised(input) { return reading(.factorise(algebra)) }
        if let simplification = Simplification.parse(input) { return reading(.simplify(simplification)) }
        if let trig = TrigSimplification.parse(input) { return reading(.trigIdentity(trig)) }
        // One equation in one unknown: the tree read once, with the parts the letters were given.
        guard let equation = Analyzer.equation(roles) ?? (try? Parser.parse(input)) else {
            // A formula turned round, letters that stand together, or too few equations.
            if let turned = Rearrangement.parse(input, for: asked?.letter) { return reading(.rearrange(turned)) }
            if let grouped = Grouped.parse(input), let solution = grouped.solution { return reading(.grouped(grouped, solution)) }
            return Insufficient.parse(input).map { reading(.insufficient($0)) }
        }
        return Solver.solve(equation).map { reading(.solveEquation(equation, $0)) }
    }

    // The one equation of the reading, its one unknown and its constants written in, from the tree;
    // nil where the roles leave the unknown undecided, as 2c = g, for the parser's own rules.
    static func equation(_ roles: Roles?) -> Equation? {
        guard let roles, roles.tree.count == 1, let statement = roles.tree.first, let right = statement.right,
              roles.unknowns.count == 1, let unknown = roles.unknowns.first, roles.parameters.isEmpty else { return nil }
        let constants = Set(roles.constants)
        return Equation(left: statement.left.lowered(unknown: unknown, constants: constants, euler: roles.euler),
                        right: right.lowered(unknown: unknown, constants: constants, euler: roles.euler), unknown: unknown)
    }

    // x⁶ − 7x⁴ + 14x² − 8 as (x + 2)(x + 1)(x − 1)(x − 2)(x² − 2): a polynomial in one letter
    // typed out in full, with no brackets, that has a factorisation saying more than tidying would.
    static func factorised(_ input: String) -> Algebra? {
        guard !input.contains("("), !input.hasPrefix("="), let tokens = try? Parser.tokenize(input),
              case let letters = Set(tokens.compactMap({ if case .letter(let l) = $0 { l } else { nil } })), letters.count == 1,
              let name = letters.first, name != "e", let expr = try? Parser.parse(input + "=0").left,
              let p = poly(expr).map(trim), p.count >= 3, integerCoefficients(p) != nil,
              let algebra = Algebra.parse("factor(\(input))"), algebra.solution.exact.contains("(") else { return nil }
        // Two factors with the letter in them or one repeated, (x + 1)²; a number taken out of what
        // does not factorise, (x³ + 2x + 2)/2, is none.
        let shown = algebra.solution.exact
        let groups = shown.filter { $0 == "(" }.count, repeated = shown.range(of: "\\)[²³⁴⁵⁶⁷⁸⁹]", options: .regularExpression) != nil
        let bare = shown.range(of: "^[0-9]*[a-z]", options: .regularExpression) != nil
        guard groups >= 2 || repeated || (bare && groups >= 1) else { return nil }
        // Where tidying says as much, x² + x as x(x + 1), the tidying is the card.
        if let tidied = Simplification.parse(input), tidied.solution.exact == "= " + shown { return nil }
        return algebra
    }
}

// The question first, whatever order it was written in: m = 55, v = 0.9, mg·1.2 + ½mv² = ? is read as
// mg·1.2 + ½mv², m = 55, v = 0.9; a = ?, F = ma as F = ma, a = ?; and 0 ≤ x < 360°, sin x = 0.5 as
// sin x = 0.5, 0 ≤ x < 360°. The question is the one part that is neither a value given (a name
// and a number, or a matrix), nor a range, nor a name asked for (a = ?); it goes first, the values
// and ranges after it as they were, and what is asked for last. An expression asked for with = ?,
// mg·1.2 + ½mv² = ?, is the expression. Where there is no such part, as in u_1 = 12, u_5 = 29,
// u_10 = ?, or more than one, as in a system, the text is left as it was.
enum Ordering {
    static func questionFirst(_ input: String) -> String {
        let parts = Taylor.topLevel(input).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return input }
        var questions: [String] = [], given: [String] = [], asked: [String] = []
        for part in parts {
            // a = ? asks for a, and so does a letter by itself, as d asks for a common difference.
            if part.range(of: "^[A-Za-z_0-9θωλαβφρτμεσ]+\\s*=\\s*\\?$", options: .regularExpression) != nil
                || part.range(of: "^[A-Za-zθωλαβφρτμεσ]$", options: .regularExpression) != nil { asked.append(part) }
            else if isGiven(part) || part.contains(where: { "<>≤≥∈".contains($0) }) { given.append(part) }
            else { questions.append(part) }
        }
        guard questions.count == 1 else { return input }
        var question = questions[0]
        // An expression with = ? after it, and no other =, asks for the expression.
        if question.range(of: "=\\s*\\?$", options: .regularExpression) != nil, question.filter({ $0 == "=" }).count == 1 {
            question = question.replacingOccurrences(of: "\\s*=\\s*\\?$", with: "", options: .regularExpression)
        }
        let reordered = ([question] + given + asked).joined(separator: ", ")
        return question == parts[0] && reordered.filter({ !$0.isWhitespace }) == input.filter({ !$0.isWhitespace }) ? input : reordered
    }

    // A name and its value: n = 1/2, θ = 30°, theta = pi/6, A = [[2, 3], [1, 4]].
    private static func isGiven(_ part: String) -> Bool {
        let sides = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard sides.count == 2, sides[0].range(of: "^[A-Za-zθωλαβφρτμεσ][A-Za-z0-9_θωλαβφρτμεσ]*$", options: .regularExpression) != nil,
              !sides[1].contains("=") else { return false }
        return sides[1].hasPrefix("[") || (try? Parser.constant(sides[1])) != nil
    }
}
