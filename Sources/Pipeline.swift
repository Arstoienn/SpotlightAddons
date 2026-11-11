import Foundation

// Everything said about one input, from the one reading of it: the card, the working, what is
// copied and what ans becomes. The input is read once, by the first part of the solver that
// takes it, and each of these is then that part's own; the working and the rest are only made
// when they are asked for.
final class Answer {
    let solution: Solution
    private let makeDetails: () -> Details?
    private let makeCopy: () -> String?
    private let makeValues: () -> [Double]
    private let makeInterpretation: (() -> Math?)?

    init(_ solution: Solution, details: @escaping () -> Details?, copy: @escaping () -> String?, values: @escaping () -> [Double],
         interpretation: (() -> Math?)? = nil) {
        self.solution = solution
        makeDetails = details
        makeCopy = copy
        makeValues = values
        makeInterpretation = interpretation
    }

    lazy var details: Details? = makeDetails()
    // How the question was read, where the person typing should know: 1/ax² taken as (1/a)x², x ≠ 2.
    var notes: [String] = []
    // Statements in brackets taken as 1 or 0, which the working begins with.
    var judged: [String] = []
    // The card's sign, saying what kind of answer this is (MathIntent.symbol).
    var symbol = "function"
    // The colour shown in place of the sign, for a colour.
    var swatch: Swatch?
    lazy var copy: String? = makeCopy()
    lazy var values: [Double] = makeValues()
    // What the input was understood to be, typeset: the heading of the working, with the values
    // given where there are some.
    lazy var interpretation: Math? = makeInterpretation?() ?? details?.equation
}

extension Solver {
    private static func number(_ x: Double) -> String { x == 0 ? "0" : String(format: "%.12g", x) }
    private static func plain(_ s: String) -> String { s.replacingOccurrences(of: "−", with: "-") }

    // An answer whose working gives the roots: they are what is copied, and what ans becomes.
    private static func rooted(_ solution: Solution, _ details: @escaping () -> Details?) -> Answer {
        let answer = Answer(solution, details: details, copy: { nil }, values: { [] })
        return Answer(solution, details: { answer.details },
                      copy: { answer.details.map { $0.roots.isEmpty ? plain(solution.exact) : $0.roots.map(number).joined(separator: ", ") } },
                      values: { answer.details?.roots ?? [] })
    }

    // Ways of writing a question that another part of the solver reads, written as it reads them:
    // A^(-1), A = [[2,1],[1,2]] with the matrix written in for A; d/dx (f)|_x=1, as LaTeX gives
    // \left.\frac{d}{dx}(f)\right|_{x=1}, as derivative(f, 1).
    static func rewritten(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespaces)
        // Matrices and vectors given by name, before the question or after it, and the one part
        // that is not such a name is the question, with or without =? after it: A = [[2,3],[1,4]],
        // B = [[1,5],[2,3]], A + B = ?, as on paper, and A + B, A = …, B = … alike.
        let parts = Taylor.topLevel(text)
        if parts.count >= 2 {
            var named: [(String, String)] = [], questions: [String] = []
            for part in parts {
                let sides = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if sides.count == 2, sides[0].range(of: "^[A-Za-z]$", options: .regularExpression) != nil, sides[0] != "e", sides[0] != "i", sides[1].hasPrefix("[") {
                    named.append((sides[0], sides[1]))
                } else {
                    questions.append(part)
                }
            }
            if !named.isEmpty, questions.count == 1 {
                var expression = questions[0].replacingOccurrences(of: "\\s*=\\s*\\?\\s*$", with: "", options: .regularExpression)
                // Names side by side are a product, AB as on paper, as is a number before one, 2A:
                // a run of letters every one of which is a name given, with the number before it.
                let names = Set(named.map(\.0))
                var spaced = "", run = ""
                func flush() {
                    if !run.isEmpty, run.count > 1, run.allSatisfy({ names.contains(String($0)) }) { spaced += run.map(String.init).joined(separator: "*") } else { spaced += run }
                    run = ""
                }
                for c in expression {
                    if c.isLetter { if run.isEmpty, let last = spaced.last, last.isNumber || last == ")", names.contains(String(c)) { spaced += "*" }; run.append(c) }
                    else { flush(); spaced.append(c) }
                }
                flush()
                expression = spaced
                for (name, matrix) in named {
                    expression = expression.replacingOccurrences(of: "(?<![A-Za-z])\(name)(?![A-Za-z])", with: "(\(matrix))", options: .regularExpression)
                }
                text = expression.trimmingCharacters(in: .whitespaces)
            }
        }
        // A derivative at a point.
        let at = try! NSRegularExpression(pattern: "^d/d([a-z])\\s*(.+?)\\s*\\|_?\\{?\\(?\\s*\\1\\s*=\\s*([^(){}|]+?)\\s*\\)?\\}?$")
        if let m = at.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let f = Range(m.range(at: 2), in: text), let a = Range(m.range(at: 3), in: text) {
            text = "derivative(\(text[f]), \(text[a]))"
        }
        return text
    }

    // The card, the working, the copy and ans for what the input was read as.
    static func answer(_ typed: String) -> Answer? {
        guard let reading = Analyzer.read(typed) else { return nil }
        return answer(for: reading)
    }

    static func answer(for reading: Reading) -> Answer? {
        let answer: Answer?
        switch reading.intent {
        // Running a command copies nothing, and leaves ans as it was.
        case .command(let command): answer = Answer(command.solution, details: { nil }, copy: { nil }, values: { [] })
        case .place(let place): answer = Answer(place.solution, details: { nil }, copy: { nil }, values: { [] })
        case .astronomy(let sky):
            answer = Answer(sky.solution, details: { sky.details }, copy: { sky.copy }, values: { sky.value.map { [$0] } ?? [] })
        case .money(let money):
            answer = Answer(money.solution, details: { money.details }, copy: { money.copyText }, values: { money.value.isFinite ? [money.value] : [] })
        case .digest(let hash): answer = Answer(hash.solution, details: { hash.details }, copy: { hash.written }, values: { [] })
        case .colour(let colour):
            answer = Answer(colour.solution, details: { colour.details }, copy: { colour.copyText }, values: { [] })
            answer?.swatch = colour.swatch
        case .sequence(let sequence):
            answer = Answer(sequence.solution, details: { sequence.details }, copy: { sequence.copyText }, values: { sequence.values })
        case .severalAnswers(let count, let named):
            answer = Answer(Solution(exact: "ans has \(count) values", approx: "Write \(named)\(count > 4 ? ", …" : "")."), details: { nil }, copy: { nil }, values: { [] })
        case .matrix(let matrix):
            answer = Answer(matrix.solution, details: { matrix.details }, copy: { matrix.copyText }, values: { matrix.values })
        case .differentialEquation(let equation):
            answer = Answer(equation.solution, details: { equation.details }, copy: { plain(equation.solution.exact) }, values: { [] })
        case .angleIdentity(let identity):
            answer = Answer(identity.solution, details: { identity.details }, copy: { nil }, values: { [] })
        case .euler(let euler):
            answer = Answer(euler.solution, details: { euler.details }, copy: { String(format: "%.12g", euler.values[0]) }, values: { euler.values })
        case .taylor(let taylor):
            answer = Answer(taylor.solution, details: { taylor.details }, copy: { plain(taylor.polynomial.plain) }, values: { [] })
        case .namedOperation(let algebra):
            answer = Answer(algebra.solution, details: { algebra.details }, copy: { algebra.copyText }, values: { algebra.values })
        case .solveInRange(let domain):
            answer = Answer(domain.solution, details: { domain.details }, copy: { domain.copyText }, values: { domain.roots })
        case .givenValues(let given):
            answer = Answer(given.solution, details: { given.details }, copy: { given.copyText }, values: { given.values },
                            interpretation: { given.interpretation })
        case .linearSystem(let system):
            let rooted = rooted(system.solution) { system.details }
            answer = Answer(system.solution, details: { rooted.details }, copy: { rooted.copy }, values: { [] })
        case .nonlinearSystem(let system):
            let rooted = rooted(system.solution) { system.details }
            answer = Answer(system.solution, details: { rooted.details }, copy: { rooted.copy }, values: { [] })
        case .letterSystem(let lettered):
            answer = Answer(lettered.solution, details: { lettered.details }, copy: { plain(lettered.solution.exact) }, values: { [] })
        case .insufficient(let wanting): answer = Answer(wanting.solution, details: { wanting.details }, copy: { nil }, values: { [] })
        case .conversion(let conversion):
            answer = Answer(conversion.solution, details: { conversion.details }, copy: { conversion.copyText }, values: { [conversion.value] })
        case .complex(let complex):
            answer = Answer(complex.solution, details: { complex.details }, copy: { complex.copyText }, values: { complex.values })
        case .numberFacts(let number): answer = Answer(number.solution, details: { number.details }, copy: { nil }, values: { [] })
        case .logic(let logic):
            answer = Answer(logic.solution, details: { logic.details }, copy: { logic.holds ? "True" : "False" }, values: { [] })
        case .comparison(let comparison):
            answer = Answer(comparison.solution, details: { comparison.details }, copy: { comparison.holds ? "True" : "False" }, values: { [] })
        case .inequality(let inequality):
            answer = Answer(inequality.solution, details: { inequality.details }, copy: { plain(inequality.solution.exact) }, values: { [] })
        case .inequalities(let inequalities):
            answer = Answer(inequalities.solution, details: { inequalities.details }, copy: { plain(inequalities.solution.exact) }, values: { [] })
        case .evaluate(let evaluation, let solution, let asTyped):
            answer = Answer(solution, details: {
                var d = evaluationDetails(evaluation)
                // (20/3) as it was written: the brackets are kept, as they were typed.
                if evaluation.name == nil, wholly(bracketed: asTyped.replacingOccurrences(of: "\\left(", with: "(").replacingOccurrences(of: "\\right)", with: ")")) { d.equation = .group(d.equation) }
                return d
            }, copy: {
                let v = evaluation.value
                if abs(v) >= 1e15, evaluation.expr.constants.isEmpty, let big = evaluation.expr.exactInteger, big.digitCount <= 60 { return plain(big.description) }
                return v.isFinite && !evaluation.isLost ? number(v) : nil
            }, values: { evaluation.value.isFinite && !evaluation.isLost ? [evaluation.value] : [] })
        case .factorise(let algebra):
            answer = Answer(Solution(exact: "= " + algebra.solution.exact, approx: "Factorised"), details: { algebra.details }, copy: { algebra.copyText }, values: { [] })
        case .simplify(let simplification):
            answer = Answer(simplification.solution, details: { simplification.details }, copy: { plain(simplification.result.plain) }, values: { [] })
        case .trigIdentity(let trig): answer = Answer(trig.solution, details: { trig.details }, copy: { trig.copyText }, values: { [] })
        case .rearrange(let turned):
            let rooted = rooted(turned.solution) { turned.details }
            answer = Answer(turned.solution, details: { rooted.details }, copy: { rooted.copy }, values: { [] })
        case .grouped(let grouped, let solution): answer = rooted(solution) { grouped.details }
        case .solveEquation(let equation, let solution): answer = rooted(solution) { details(of: equation) }
        }
        answer?.notes = reading.notes
        answer?.judged = reading.judged
        answer?.symbol = reading.intent.symbol
        return answer
    }
}
