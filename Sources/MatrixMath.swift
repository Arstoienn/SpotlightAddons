import Foundation

// Matrices and vectors written as [[1, 2], [3, 4]] and [1, 2, 3]: det, inv, transpose, trace, rank,
// dot, cross, norm, and sums, products and powers of them.
struct MatrixValue {
    enum Value {
        case scalar(Double)
        case vector([Double])
        case matrix([[Double]])
        case undefined(String)
        case text(String, copy: String)    // a line to be read, y = 2x + 1
    }

    var value: Value
    var source: String

    private struct Failure: Error {}
    private struct Undefined: Error { var reason: String }

    // Whether it is for this: a square bracket in it, and it reads.
    static func parse(_ input: String) -> MatrixValue? {
        guard input.contains("[") || input.lowercased().contains("identity("), !input.contains("=") else { return nil }
        var reader = Reader(chars: Array(input.filter { $0 != " " }))
        let v: Value
        do { v = try reader.expression() } catch let e as Undefined {
            guard reader.sawBracket else { return nil }
            return MatrixValue(value: .undefined(e.reason), source: input)
        } catch { return nil }
        guard reader.at == reader.chars.count, reader.sawBracket || reader.operations > 0 else { return nil }
        // Entries beyond what can be held, or no number at all, are no answer to show and copy.
        let entries: [Double]
        switch v { case .vector(let e): entries = e; case .matrix(let m): entries = m.flatMap { $0 }; default: entries = [] }
        if !entries.allSatisfy(\.isFinite) {
            return MatrixValue(value: .undefined(entries.contains(where: \.isNaN) ? "Some of its entries have no value." : "Its entries are beyond the largest number that can be held, about 1.8×10³⁰⁸."), source: input)
        }
        // A lone literal is nothing asked for.
        if case .matrix = v, input.trimmingCharacters(in: .whitespaces).hasPrefix("["), reader.operations == 0 { return nil }
        if case .vector = v, input.trimmingCharacters(in: .whitespaces).hasPrefix("["), reader.operations == 0 { return nil }
        return MatrixValue(value: v, source: input)
    }

    private struct Reader {
        var chars: [Character]
        var at = 0
        var sawBracket = false
        var operations = 0   // functions and operators applied: a bare literal has none

        func peek() -> Character? { at < chars.count ? chars[at] : nil }
        mutating func take(_ c: Character) -> Bool { if peek() == c { at += 1; return true }; return false }

        mutating func expression() throws -> Value {
            var left = try term()
            while let c = peek(), c == "+" || c == "-" {
                at += 1
                let right = try term()
                operations += 1
                left = try MatrixValue.combine(c, left, right)
            }
            return left
        }

        mutating func term() throws -> Value {
            var left = try unary()
            while let c = peek(), c == "*" || c == "/" || c == "×" || c == "·" || c == "÷" {
                at += 1
                let right = try unary()
                operations += 1
                left = try MatrixValue.combine(c == "/" || c == "÷" ? "/" : "*", left, right)
            }
            return left
        }

        mutating func unary() throws -> Value {
            if take("-") { operations += 1; return try MatrixValue.scale(try unary(), -1) }
            if take("+") { return try unary() }
            return try power()
        }

        mutating func power() throws -> Value {
            let base = try primary()
            if take("^") || take("ᵀ") {
                operations += 1
                if chars[at - 1] == "ᵀ" { return try MatrixValue.transpose(base) }
                // ^T and ^(T): the transpose.
                if let c = peek(), c == "T" || c == "t", at + 1 >= chars.count || !chars[at + 1].isLetter { at += 1; return try MatrixValue.transpose(base) }
                if at + 2 < chars.count, chars[at] == "(", chars[at + 1] == "T", chars[at + 2] == ")" { at += 3; return try MatrixValue.transpose(base) }
                let negative = take("-")
                let exponent = try unaryScalar()
                return try MatrixValue.raise(base, negative ? -exponent : exponent)
            }
            return base
        }

        mutating func unaryScalar() throws -> Double {
            var number = ""
            if take("(") {
                let inner = try expression()
                guard take(")"), case .scalar(let v) = inner else { throw Failure() }
                return v
            }
            while let c = peek(), c.isNumber || c == "." { number.append(c); at += 1 }
            guard let v = Double(number) else { throw Failure() }
            return v
        }

        // A matrix: a list of lists; a vector: a list of numbers.
        mutating func list() throws -> Value {
            sawBracket = true
            var rows: [[Double]] = [], flat: [Double] = []
            var nested = false
            if take("]") { throw Failure() }
            repeat {
                if peek() == "[" {
                    at += 1
                    nested = true
                    guard case .vector(let row) = try list() else { throw Failure() }
                    rows.append(row)
                } else {
                    guard case .scalar(let v) = try expression() else { throw Failure() }
                    flat.append(v)
                }
            } while take(",")
            guard take("]") else { throw Failure() }
            if nested {
                guard flat.isEmpty, let width = rows.first?.count, width > 0, rows.allSatisfy({ $0.count == width }) else { throw Failure() }
                return .matrix(rows)
            }
            return .vector(flat)
        }

        mutating func primary() throws -> Value {
            guard let c = peek() else { throw Failure() }
            if c == "[" { at += 1; return try list() }
            if c == "(" {
                at += 1
                let v = try expression()
                guard take(")") else { throw Failure() }
                return v
            }
            if c.isNumber || c == "." {
                var number = ""
                while let d = peek(), d.isNumber || d == "." { number.append(d); at += 1 }
                // 1e-3
                if let e = peek(), e == "e" || e == "E", at + 1 < chars.count, chars[at + 1].isNumber || chars[at + 1] == "-" {
                    number.append("e"); at += 1
                    if take("-") { number.append("-") }
                    while let d = peek(), d.isNumber { number.append(d); at += 1 }
                }
                guard let v = Double(number) else { throw Failure() }
                return .scalar(v)
            }
            if c == "π" { at += 1; return .scalar(.pi) }
            guard c.isLetter else { throw Failure() }
            var name = ""
            while let d = peek(), d.isLetter { name.append(d); at += 1 }
            if name == "pi" { return .scalar(.pi) }
            if name == "e" { return .scalar(M_E) }
            guard take("(") else { throw Failure() }
            var args: [Value] = []
            if peek() != ")" { repeat { args.append(try expression()) } while take(",") }
            guard take(")") else { throw Failure() }
            operations += 1
            return try MatrixValue.apply(name.lowercased(), args)
        }
    }

    // MARK: Operations

    private static func combine(_ op: Character, _ a: Value, _ b: Value) throws -> Value {
        switch (a, b) {
        case (.scalar(let x), .scalar(let y)):
            if op == "/", y == 0 { throw Undefined(reason: "It is divided by zero.") }
            return .scalar(op == "+" ? x + y : op == "-" ? x - y : op == "*" ? x * y : x / y)
        case (.scalar(let k), .matrix), (.scalar(let k), .vector):
            guard op == "*" else { throw Failure() }
            return try scale(b, k)
        case (.matrix, .scalar(let k)), (.vector, .scalar(let k)):
            if op == "*" { return try scale(a, k) }
            if op == "/" {
                guard k != 0 else { throw Undefined(reason: "A vector or a matrix cannot be divided by zero.") }
                return try scale(a, 1 / k)
            }
            throw Failure()
        case (.vector(let u), .vector(let v)):
            guard u.count == v.count, op == "+" || op == "-" else { throw Failure() }
            return .vector(zip(u, v).map { op == "+" ? $0 + $1 : $0 - $1 })
        case (.matrix(let m), .matrix(let n)):
            if op == "*" { return try multiply(m, n) }
            guard m.count == n.count, m[0].count == n[0].count else { throw Undefined(reason: "The matrices have different sizes.") }
            return .matrix(zip(m, n).map { zip($0, $1).map { op == "+" ? $0 + $1 : $0 - $1 } })
        case (.matrix(let m), .vector(let v)):
            guard op == "*" else { throw Failure() }
            guard case .matrix(let product) = try multiply(m, v.map { [$0] }) else { throw Failure() }
            return .vector(product.map { $0[0] })
        case (.vector(let v), .matrix(let m)):
            guard op == "*", case .matrix(let product) = try multiply([v], m) else { throw Failure() }
            return .vector(product[0])
        default: throw Failure()
        }
    }

    private static func scale(_ a: Value, _ k: Double) throws -> Value {
        switch a {
        case .scalar(let x): return .scalar(x * k)
        case .vector(let v): return .vector(v.map { $0 * k })
        case .matrix(let m): return .matrix(m.map { $0.map { $0 * k } })
        case .undefined, .text: throw Failure()
        }
    }

    private static func multiply(_ a: [[Double]], _ b: [[Double]]) throws -> Value {
        guard a[0].count == b.count else { throw Undefined(reason: "The columns of the first matrix are not as many as the rows of the second.") }
        return .matrix(a.map { row in (0..<b[0].count).map { j in row.indices.reduce(0) { $0 + row[$1] * b[$1][j] } } })
    }

    private static func transpose(_ a: Value) throws -> Value {
        guard case .matrix(let m) = a else { throw Failure() }
        return .matrix((0..<m[0].count).map { j in m.map { $0[j] } })
    }

    private static func identity(_ n: Int) -> [[Double]] { (0..<n).map { i in (0..<n).map { $0 == i ? 1 : 0 } } }

    private static func raise(_ a: Value, _ n: Double) throws -> Value {
        switch a {
        case .scalar(let x): return .scalar(pow(x, n))
        case .matrix(let m):
            guard m.count == m[0].count, n == n.rounded(), abs(n) <= 64 else { throw Failure() }
            var base = m
            if n < 0 { guard let inverse = inverse(m) else { throw Undefined(reason: "The matrix is singular: its determinant is 0, and it has no inverse.") }; base = inverse }
            var result = identity(m.count)
            for _ in 0..<Int(abs(n)) { guard case .matrix(let p) = try multiply(result, base) else { throw Failure() }; result = p }
            return .matrix(result)
        default: throw Failure()
        }
    }

    // Gaussian elimination with the largest pivot chosen; the determinant comes out of the same.
    private static func eliminate(_ m: [[Double]]) -> (determinant: Double, rank: Int, reduced: [[Double]]) {
        var a = m
        let rows = a.count, cols = a[0].count
        var determinant = 1.0, rank = 0
        for col in 0..<cols where rank < rows {
            var pivot = rank
            for r in rank..<rows where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-12 * max(1, a.flatMap { $0 }.map(abs).max() ?? 1) else { determinant = 0; continue }
            if pivot != rank { a.swapAt(pivot, rank); determinant = -determinant }
            determinant *= a[rank][col]
            for r in (rank + 1)..<rows {
                let f = a[r][col] / a[rank][col]
                for c in col..<cols { a[r][c] -= f * a[rank][c] }
            }
            rank += 1
        }
        return (rows == cols ? determinant : 0, rank, a)
    }

    private static func inverse(_ m: [[Double]]) -> [[Double]]? {
        let n = m.count
        guard n == m[0].count else { return nil }
        var a = zip(m, identity(n)).map { $0 + $1 }
        for col in 0..<n {
            var pivot = col
            for r in col..<n where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-12 * max(1, m.flatMap { $0 }.map(abs).max() ?? 1) else { return nil }
            a.swapAt(pivot, col)
            let d = a[col][col]
            a[col] = a[col].map { $0 / d }
            for r in 0..<n where r != col {
                let f = a[r][col]
                for c in 0..<(2 * n) { a[r][c] -= f * a[col][c] }
            }
        }
        return a.map { Array($0[n...]) }
    }

    // The p-th percentile, from 0 to 100, by linear interpolation between the sorted values.
    private static func percentile(_ v: [Double], _ p: Double) -> Double {
        let s = v.sorted()
        guard let first = s.first else { return .nan }
        let position = Double(s.count - 1) * p / 100
        let lower = Int(position.rounded(.down)), upper = min(lower + 1, s.count - 1)
        return s.count == 1 ? first : s[lower] + (s[upper] - s[lower]) * (position - Double(lower))
    }

    private static func apply(_ name: String, _ args: [Value]) throws -> Value {
        func matrix(_ i: Int = 0) throws -> [[Double]] {
            guard i < args.count else { throw Failure() }
            switch args[i] {
            case .matrix(let m): return m
            case .scalar(let x): return [[x]]
            case .vector, .undefined, .text: throw Failure()
            }
        }
        func vector(_ i: Int) throws -> [Double] {
            guard i < args.count, case .vector(let v) = args[i] else { throw Failure() }
            return v
        }
        switch name {
        case "det", "determinant":
            let m = try matrix()
            guard args.count == 1 else { throw Failure() }
            guard m.count == m[0].count else { throw Undefined(reason: "The determinant is defined for a square matrix.") }
            let d = eliminate(m).determinant
            let r = d.rounded()
            return .scalar(abs(d - r) <= 1e-9 * max(1, abs(d)) ? r : d)
        case "inv", "inverse":
            guard args.count == 1 else { throw Failure() }
            let m = try matrix()
            guard m.count == m[0].count else { throw Undefined(reason: "The inverse is defined for a square matrix.") }
            guard let i = inverse(m) else { throw Undefined(reason: "The matrix is singular: its determinant is 0, and it has no inverse.") }
            return .matrix(i)
        case "transpose": return try transpose(args.count == 1 ? args[0] : .scalar(0))
        case "trace":
            let m = try matrix()
            guard args.count == 1 else { throw Failure() }
            guard m.count == m[0].count else { throw Undefined(reason: "The trace is defined for a square matrix.") }
            return .scalar(m.indices.reduce(0) { $0 + m[$1][$1] })
        case "rank":
            guard args.count == 1 else { throw Failure() }
            return .scalar(Double(eliminate(try matrix()).rank))
        case "dot":
            guard args.count == 2 else { throw Failure() }
            let (u, v) = (try vector(0), try vector(1))
            guard u.count == v.count else { throw Undefined(reason: "The vectors have different lengths.") }
            return .scalar(zip(u, v).reduce(0) { $0 + $1.0 * $1.1 })
        case "cross":
            guard args.count == 2 else { throw Failure() }
            let (u, v) = (try vector(0), try vector(1))
            guard u.count == 3, v.count == 3 else { throw Undefined(reason: "The cross product is defined for vectors of three components.") }
            return .vector([u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]])
        case "norm", "magnitude":
            guard args.count == 1 else { throw Failure() }
            switch args[0] {
            case .vector(let v): return .scalar(v.reduce(0) { $0 + $1 * $1 }.squareRoot())
            case .matrix(let m): return .scalar(m.flatMap { $0 }.reduce(0) { $0 + $1 * $1 }.squareRoot())
            case .scalar(let x): return .scalar(abs(x))
            case .undefined, .text: throw Failure()
            }
        case "quartile", "percentile":
            guard args.count == 2, case .scalar(let q) = args[1] else { throw Failure() }
            let p = name == "quartile" ? 25 * q : q
            guard p >= 0, p <= 100 else { throw Undefined(reason: "A percentile is between 0 and 100, and a quartile between 0 and 4.") }
            return .scalar(percentile(try vector(0), p))
        case "iqr":
            let v = args.count == 1 ? try vector(0) : try args.map { if case .scalar(let x) = $0 { x } else { throw Failure() } }
            return .scalar(percentile(v, 75) - percentile(v, 25))
        case "corr", "correlation", "cov", "covariance", "linreg":
            guard args.count == 2 else { throw Failure() }
            let (x, y) = (try vector(0), try vector(1))
            guard x.count == y.count, x.count >= 2 else { throw Undefined(reason: "The two lists must have the same length, of at least two.") }
            let n = Double(x.count), mx = x.reduce(0, +) / n, my = y.reduce(0, +) / n
            let sxy = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
            let sxx = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }, syy = y.reduce(0) { $0 + ($1 - my) * ($1 - my) }
            switch name {
            case "cov", "covariance": return .scalar(sxy / (n - 1))
            case "linreg":
                guard sxx > 0 else { throw Undefined(reason: "The x values are all the same.") }
                let slope = sxy / sxx, intercept = my - slope * mx
                // 9/4 x is (9/4)x, and a slope of one or minus one is x or −x.
                var coefficient = entry(slope)
                if abs(slope) == 1 { coefficient = slope < 0 ? "−" : "" } else if coefficient.contains("/") { coefficient = "(\(coefficient))" }
                let shown = abs(intercept) < 1e-12 ? "y = \(coefficient)x" : "y = \(coefficient)x \(intercept < 0 ? "−" : "+") \(entry(abs(intercept)))"
                return .text(shown, copy: shown.replacingOccurrences(of: "−", with: "-"))
            default:
                guard sxx > 0, syy > 0 else { throw Undefined(reason: "A list that does not vary has no correlation.") }
                return .scalar(sxy / (sxx * syy).squareRoot())
            }
        // From a frequency table, the values and how often each comes: mean([1,2,3],[2,1,1]) is
        // the mean of 1, 1, 2 and 3, (1×2 + 2×1 + 3×1)/4 = 1.75.
        case "mean", "average", "avg", "median", "var", "variance", "varp", "stdev", "stdevp", "total":
            guard args.count == 2 else { throw Failure() }
            let (x, f) = (try vector(0), try vector(1))
            guard x.count == f.count, !x.isEmpty else { throw Undefined(reason: "There must be as many frequencies as values.") }
            guard f.allSatisfy({ $0 >= 0 }) else { throw Undefined(reason: "A frequency cannot be below nought.") }
            let n = f.reduce(0, +)
            guard n > 0 else { throw Undefined(reason: "The frequencies add up to nought.") }
            let mean = zip(x, f).reduce(0) { $0 + $1.0 * $1.1 } / n
            let squares = zip(x, f).reduce(0) { $0 + $1.1 * ($1.0 - mean) * ($1.0 - mean) }
            switch name {
            case "mean", "average", "avg": return .scalar(mean)
            case "total": return .scalar(zip(x, f).reduce(0) { $0 + $1.0 * $1.1 })
            case "varp": return .scalar(squares / n)
            case "stdevp": return .scalar((squares / n).squareRoot())
            case "var", "variance", "stdev":
                guard n > 1 else { throw Undefined(reason: "A sample of one has no variance.") }
                return .scalar(name == "stdev" ? (squares / (n - 1)).squareRoot() : squares / (n - 1))
            default:
                // The middle of the values in order, each counted as often as it comes.
                guard f.allSatisfy({ $0 == $0.rounded() }), n <= 1_000_000 else { throw Undefined(reason: "A median needs whole frequencies.") }
                let ordered = zip(x, f).sorted { $0.0 < $1.0 }
                func at(_ k: Double) -> Double {
                    var seen = 0.0
                    for (value, count) in ordered { seen += count; if seen >= k { return value } }
                    return ordered.last!.0
                }
                return .scalar(n.truncatingRemainder(dividingBy: 2) == 1 ? at((n + 1) / 2) : (at(n / 2) + at(n / 2 + 1)) / 2)
            }
        case "identity":
            guard args.count == 1, case .scalar(let n) = args[0], n == n.rounded(), n >= 1, n <= 20 else { throw Failure() }
            return .matrix(identity(Int(n)))
        default:
            guard args.count == 1, case .scalar(let x) = args[0], Functions.names.contains(name) else { throw Failure() }
            return .scalar(Functions.apply(name, x))
        }
    }

    // MARK: Showing

    // A number as a fraction where one of modest size is it to full precision, found by continued
    // fractions; otherwise a decimal.
    private static func entry(_ x: Double) -> String {
        if abs(x) < 1e-12 { return "0" }
        guard Options.exact, abs(x) < 1e9 else { return decimal(x) }
        var (h1, h0, k1, k0) = (1.0, 0.0, 0.0, 1.0)
        var y = abs(x)
        for _ in 0..<40 {
            let a = y.rounded(.down)
            (h1, h0) = (a * h1 + h0, h1)
            (k1, k0) = (a * k1 + k0, k1)
            if k1 > 1e6 { break }
            if abs(h1 / k1 - abs(x)) <= 1e-10 * max(1, abs(x)) { return fraction(Int(x < 0 ? -h1 : h1), Int(k1)) }
            let rest = y - a
            if rest < 1e-13 { break }
            y = 1 / rest
        }
        return decimal(x)
    }

    // A matrix drawn as one, between square brackets; a vector as a single row of them.
    static func math(_ m: [[Double]]) -> Math { .matrix(m.map { $0.map { t(entry($0)) } }) }
    static func math(_ v: [Double]) -> Math { .matrix([v.map { t(entry($0)) }]) }

    // The result drawn: a matrix or vector as one, anything else as its line.
    var resultMath: Math {
        switch value {
        case .matrix(let m): return MatrixValue.math(m)
        case .vector(let v): return MatrixValue.math(v)
        default: return t(text)
        }
    }

    // What was typed, drawn: each [[…]] and […] as a matrix, inv(A) as A⁻¹ and transpose(A) as Aᵀ,
    // det(A) and the rest with their names before them; nil where it does not read, and the text
    // is shown as it was typed.
    var shown: Math? {
        var reader = Display(chars: Array(source.filter { $0 != " " }))
        guard let m = try? reader.expression(), reader.at == reader.chars.count else { return nil }
        return m
    }

    private struct Display {
        var chars: [Character]
        var at = 0

        func peek() -> Character? { at < chars.count ? chars[at] : nil }
        mutating func take(_ c: Character) -> Bool { if peek() == c { at += 1; return true }; return false }
        static func isMatrix(_ m: Math) -> Bool { if case .matrix = m { true } else if case .power(.matrix, _) = m { true } else { false } }

        mutating func expression() throws -> Math {
            var parts = [try term()]
            while let c = peek(), c == "+" || c == "-" {
                at += 1
                parts += [t(c == "+" ? " + " : " − "), try term()]
            }
            return parts.count == 1 ? parts[0] : .row(parts)
        }

        // A product of matrices juxtaposed, AB, as on paper; a number times one, 2A; else a dot.
        mutating func term() throws -> Math {
            var left = try unary()
            while let c = peek(), "*/×·÷".contains(c) {
                at += 1
                let right = try unary()
                if c == "/" || c == "÷" { left = .fraction(left, right); continue }
                left = Display.isMatrix(right) ? row(left, t(" "), right) : row(left, t("·"), right)
            }
            return left
        }

        mutating func unary() throws -> Math {
            if take("-") { return row(t("−"), try unary()) }
            if take("+") { return try unary() }
            return try power()
        }

        mutating func power() throws -> Math {
            let base = try primary()
            guard take("^") || take("ᵀ") else { return base }
            if chars[at - 1] == "ᵀ" { return .power(base, t("T")) }
            if take("(") {
                let inside = try expression()
                guard take(")") else { throw Failure() }
                return .power(base, inside)
            }
            if let c = peek(), c == "T" || c == "t" { at += 1; return .power(base, t("T")) }
            var exponent = take("-") ? "−" : ""
            while let c = peek(), c.isNumber || c == "." { exponent.append(c); at += 1 }
            guard exponent.contains(where: \.isNumber) else { throw Failure() }
            return .power(base, t(exponent))
        }

        mutating func list() throws -> Math {
            var rows: [[Math]] = [], flat: [Math] = []
            repeat {
                if take("[") {
                    var row: [Math] = []
                    repeat { row.append(try expression()) } while take(",")
                    guard take("]") else { throw Failure() }
                    rows.append(row)
                } else {
                    flat.append(try expression())
                }
            } while take(",")
            guard take("]") else { throw Failure() }
            return .matrix(rows.isEmpty ? [flat] : rows)
        }

        mutating func primary() throws -> Math {
            guard let c = peek() else { throw Failure() }
            if take("[") { return try list() }
            if take("(") {
                let inside = try expression()
                guard take(")") else { throw Failure() }
                return .group(inside)
            }
            if c.isNumber || c == "." {
                var number = ""
                while let d = peek(), d.isNumber || d == "." || ((d == "e" || d == "E") && number.last?.isNumber == true) { number.append(d); at += 1 }
                return t(number)
            }
            if take("π") { return t("π") }
            guard c.isLetter else { throw Failure() }
            var name = ""
            while let d = peek(), d.isLetter { name.append(d); at += 1 }
            if name == "pi" { return t("π") }
            if name == "e" { return t("e") }
            guard take("(") else { throw Failure() }
            var args: [Math] = []
            if peek() != ")" { repeat { args.append(try expression()) } while take(",") }
            guard take(")") else { throw Failure() }
            switch name.lowercased() {
            case "inv", "inverse" where args.count == 1: return .power(args[0], t("−1"))
            case "transpose" where args.count == 1: return .power(args[0], t("T"))
            default:
                // det A with the matrix after its name; the rest as name(a, b).
                if args.count == 1, Display.isMatrix(args[0]) { return row(t(name.lowercased() + " "), args[0]) }
                var parts: [Math] = []
                for (i, a) in args.enumerated() { parts += (i > 0 ? [t(", ")] : []) + [a] }
                return row(t(name.lowercased()), .group(.row(parts)))
            }
        }
    }

    var text: String {
        switch value {
        case .scalar(let x): return "= " + MatrixValue.entry(x)
        case .vector(let v): return "[" + v.map(MatrixValue.entry).joined(separator: ", ") + "]"
        case .matrix(let m): return "[" + m.map { "[" + $0.map(MatrixValue.entry).joined(separator: ", ") + "]" }.joined(separator: ", ") + "]"
        case .undefined: return "Undefined"
        case .text(let line, _): return line
        }
    }

    var solution: Solution {
        if case .scalar(let x) = value {
            let line = Evaluation(name: nil, expr: .num(x)).solution
            return line ?? Solution(exact: text, approx: nil)
        }
        if case .undefined(let why) = value { return Solution(exact: "Undefined", approx: why) }
        return Solution(exact: text, approx: nil)
    }

    var copyText: String {
        switch value {
        case .scalar(let x): return String(format: "%.12g", x)
        case .undefined: return ""
        case .text(_, let copy): return copy
        default: return text.replacingOccurrences(of: "−", with: "-")
        }
    }

    var values: [Double] { if case .scalar(let x) = value { [x] } else { [] } }

    var details: Details {
        var d = Details(name: "", equation: shown ?? t(source.trimmingCharacters(in: .whitespaces)), steps: [], solutions: [], note: nil, f: { _ in .nan }, roots: [])
        let worked = working()
        switch value {
        case .scalar:
            let line = solution
            d.solutions = answerLines(line)
            d.steps = worked
        case .vector(let v):
            d.solutions = [resultMath]
            d.steps = worked.isEmpty ? [Step(label: "Working component by component", math: resultMath, note: "The vector has \(v.count) components.")] : worked
        case .matrix(let m):
            d.solutions = [resultMath]
            d.steps = worked.isEmpty ? [Step(label: "Working entry by entry", math: resultMath, note: "The result has \(m.count) rows and \(m[0].count) columns.")] : worked
        case .undefined(let why):
            d.solutions = [t("Undefined")]
            d.steps = [Step(label: "Why there is no value", math: nil, note: why)]
        case .text(let line, _):
            d.solutions = [t(line)]
            d.steps.append(Step(label: "Fitting the least-squares line", math: t(line),
                                note: "The slope is the sum of (x − x̄)(y − ȳ) over the sum of (x − x̄)², and the line passes through (x̄, ȳ)."))
        }
        return d
    }

    // The call as typed, name(a, b): the name and what each argument comes to, where the whole of
    // it is one call.
    private func call() -> (name: String, args: [Value])? {
        let chars = Array(source.filter { $0 != " " })
        guard let open = chars.firstIndex(of: "("), open > 0, chars.last == ")", chars[..<open].allSatisfy(\.isLetter) else { return nil }
        var depth = 0, parts: [String] = [], current = ""
        for (i, c) in chars[(open + 1)...].enumerated() {
            if c == "(" || c == "[" { depth += 1 }
            if c == ")" || c == "]" {
                depth -= 1
                if depth < 0 { guard open + 1 + i == chars.count - 1 else { return nil }; break }
            }
            if c == ",", depth == 0 { parts.append(current); current = "" } else { current.append(c) }
        }
        parts.append(current)
        var args: [Value] = []
        for part in parts {
            var reader = Reader(chars: Array(part))
            guard let v = try? reader.expression(), reader.at == reader.chars.count else { return nil }
            args.append(v)
        }
        return (String(chars[..<open]).lowercased(), args)
    }

    // The working of a determinant, a norm, a dot product and the like, as it would be written out
    // by hand; empty where the result is a matter of entry-by-entry arithmetic, which says so.
    private func working() -> [Step] {
        guard let (name, args) = call() else { return [] }
        func n(_ x: Double) -> String { MatrixValue.entry(x) }
        func p(_ x: Double) -> String { x < 0 ? "(\(n(x)))" : n(x) }
        func result(_ prefix: String = "= ") -> Math { t(prefix + text.replacingOccurrences(of: "= ", with: "")) }
        switch (name, args.first) {
        case ("det", .matrix(let m)?), ("determinant", .matrix(let m)?):
            guard m.count == m[0].count, args.count == 1 else { return [] }
            if m.count == 2 {
                let (a, b, c, d) = (m[0][0], m[0][1], m[1][0], m[1][1])
                return [Step(label: "Applying ad − bc", math: t("= \(p(a))×\(p(d)) − \(p(b))×\(p(c))")),
                        Step(label: "Multiplying", math: t("= \(p(a * d)) − \(p(b * c))")),
                        Step(label: "Subtracting", math: result())]
            }
            if m.count == 3 {
                func minor(_ j: Int) -> Double {
                    let cols = (0..<3).filter { $0 != j }
                    return m[1][cols[0]] * m[2][cols[1]] - m[1][cols[1]] * m[2][cols[0]]
                }
                let signs = ["", " − ", " + "]
                _ = signs
                let expansion = (0..<3).map { j in "\(j == 0 ? "" : j == 1 ? " − " : " + ")\(p(m[0][j]))×\(p(minor(j)))" }.joined()
                let terms = (0..<3).map { j in "\(j == 0 ? "" : j == 1 ? " − " : " + ")\(p(m[0][j] * minor(j)))" }.joined()
                return [Step(label: "Expanding along the first row", math: t("= " + (0..<3).map { j in
                            let cols = (0..<3).filter { $0 != j }
                            return "\(j == 0 ? "" : j == 1 ? " − " : " + ")\(p(m[0][j]))(\(p(m[1][cols[0]]))×\(p(m[2][cols[1]])) − \(p(m[1][cols[1]]))×\(p(m[2][cols[0]])))"
                        }.joined()), note: "Each entry of the row is multiplied by the determinant of what is left when its row and column are crossed out, with the signs alternating."),
                        Step(label: "Working out each minor", math: t("= " + expansion)),
                        Step(label: "Multiplying and adding", math: t("= " + terms + " = " + n({ if case .scalar(let x) = value { x } else { 0 } }()))),]
            }
            return [Step(label: "Reducing to triangular form", math: result(),
                         note: "Row operations turn the matrix into one with zeros below the diagonal. The determinant is the product of the diagonal, with the sign changed for each swap of two rows.")]
        case ("inv", .matrix(let m)?), ("inverse", .matrix(let m)?):
            guard m.count == m[0].count, args.count == 1 else { return [] }
            if m.count == 2 {
                let (a, b, c, d) = (m[0][0], m[0][1], m[1][0], m[1][1])
                let det = a * d - b * c
                return [Step(label: "Finding the determinant", math: t("det = \(p(a))×\(p(d)) − \(p(b))×\(p(c)) = \(n(det))")),
                        Step(label: "Swapping the diagonal and changing the signs of the others", math: MatrixValue.math([[d, -b], [-c, a]])),
                        Step(label: "Dividing every entry by the determinant", math: resultMath)]
            }
            return [Step(label: "Row-reducing [A | I]", math: resultMath,
                         note: "The same row operations that turn A into the identity matrix turn the identity into the inverse of A.")]
        case ("trace", .matrix(let m)?):
            guard m.count == m[0].count else { return [] }
            return [Step(label: "Adding the diagonal", math: t("= " + m.indices.map { p(m[$0][$0]) }.joined(separator: " + ") + " " + text))]
        case ("rank", .matrix?):
            return [Step(label: "Reducing to row echelon form", math: result(),
                         note: "The rank is the number of rows that are not all zeros once the matrix has been row-reduced.")]
        case ("dot", .vector(let u)?):
            guard args.count == 2, case .vector(let v) = args[1], u.count == v.count else { return [] }
            return [Step(label: "Multiplying the components", math: t("= " + zip(u, v).map { "\(p($0))×\(p($1))" }.joined(separator: " + "))),
                    Step(label: "Adding", math: t("= " + zip(u, v).map { p($0 * $1) }.joined(separator: " + ") + " " + text))]
        case ("cross", .vector(let u)?):
            guard args.count == 2, case .vector(let v) = args[1], u.count == 3, v.count == 3 else { return [] }
            return [Step(label: "Applying the cross product formula",
                         math: t("[\(p(u[1]))×\(p(v[2])) − \(p(u[2]))×\(p(v[1])), \(p(u[2]))×\(p(v[0])) − \(p(u[0]))×\(p(v[2])), \(p(u[0]))×\(p(v[1])) − \(p(u[1]))×\(p(v[0]))]"),
                         note: "(u₂v₃ − u₃v₂, u₃v₁ − u₁v₃, u₁v₂ − u₂v₁)"),
                    Step(label: "Working out each component", math: resultMath)]
        case ("norm", .vector?), ("magnitude", .vector?), ("norm", .matrix?):
            let entries: [Double]
            switch args[0] { case .vector(let v): entries = v; case .matrix(let m): entries = m.flatMap { $0 }; default: return [] }
            let squares = entries.map { $0 * $0 }
            let sum = squares.reduce(0, +)
            return [Step(label: "Squaring each component", math: t("= √(" + entries.map { "\(p($0))²" }.joined(separator: " + ") + ")")),
                    Step(label: "Adding", math: t("= √(" + squares.map(n).joined(separator: " + ") + ") = √\(n(sum))")),
                    Step(label: "Taking the square root", math: result())]
        // From a frequency table: Σfx and n, then the mean, and for a spread the squared distances
        // from it; in decimals, as such working is written, 7/4 = 1.75.
        case ("mean", .vector(let x)?), ("average", .vector(let x)?), ("avg", .vector(let x)?), ("var", .vector(let x)?), ("variance", .vector(let x)?),
             ("varp", .vector(let x)?), ("stdev", .vector(let x)?), ("stdevp", .vector(let x)?):
            guard args.count == 2, case .vector(let f) = args[1], f.count == x.count else { return [] }
            func d(_ v: Double) -> String { decimal(v) }
            func q(_ v: Double) -> String { v < 0 ? "(\(d(v)))" : d(v) }
            // = where the decimal shown is the whole of the value, 1.75; ≈ where it is cut short.
            func equals(_ v: Double) -> String { shownWhole(v) ? "= \(d(v))" : "≈ \(d(v))" }
            let count = f.reduce(0, +), total = zip(x, f).reduce(0) { $0 + $1.0 * $1.1 }, mean = total / count
            var steps = [Step(label: "Multiplying each value by its frequency", math: t("Σfx = " + zip(x, f).map { "\(q($0))×\(q($1))" }.joined(separator: " + ") + " = \(d(total))")),
                         Step(label: "Adding the frequencies", math: t("n = " + f.map(d).joined(separator: " + ") + " = \(d(count))")),
                         Step(label: "Dividing", math: t("x̄ = Σfx/n = \(d(total))/\(d(count)) \(equals(mean))"))]
            guard !["mean", "average", "avg"].contains(name) else { return steps }
            let squares = zip(x, f).reduce(0) { $0 + $1.1 * ($1.0 - mean) * ($1.0 - mean) }
            let sample = ["var", "variance", "stdev"].contains(name), divisor = sample ? count - 1 : count, variance = squares / divisor
            steps.append(Step(label: "Squaring each value's distance from the mean",
                              math: t("Σf(x − x̄)² = " + zip(x, f).map { "\(d($1))(\(d($0)) − \(d(mean)))²" }.joined(separator: " + ") + " \(equals(squares))")))
            steps.append(Step(label: sample ? "Dividing by n − 1" : "Dividing by n", math: t("σ² = \(d(squares))/\(d(divisor)) \(equals(variance))")))
            if name.hasPrefix("stdev") { steps.append(Step(label: "Taking the square root", math: t("σ = √\(d(variance)) \(equals(variance.squareRoot()))"))) }
            return steps
        case ("quartile", _), ("percentile", _), ("iqr", _):
            return [Step(label: "Ordering the values and interpolating", math: result(),
                         note: "The values are put in order, and the percentile read at its position between two of them, linearly.")]
        case ("corr", _), ("correlation", _), ("cov", _), ("covariance", _):
            return [Step(label: name.hasPrefix("cor") ? "Dividing the covariance by both spreads" : "Summing the products of the deviations", math: result(),
                         note: "Each pair is taken as its distance from the two means, (x − x̄)(y − ȳ); these are added, and divided by n − 1 for the covariance, or by √(Σ(x − x̄)² Σ(y − ȳ)²) for the correlation.")]
        case ("transpose", _):
            return [Step(label: "Swapping rows and columns", math: resultMath, note: "Entry (i, j) of the result is entry (j, i) of the matrix.")]
        default:
            return []
        }
    }
}
