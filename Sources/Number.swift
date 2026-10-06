import Foundation

// A number typed by itself has nothing to solve or work out, but something can still be said of
// it: a whole number is the product of its primes, 2048 = 2¹¹, or is one; a decimal is a
// fraction, 0.375 = 3/8.
struct NumberFacts {
    var text: String          // as typed
    var whole: Int?           // 2048
    var fraction: (Int, Int)? // 0.375 as 375 over 1000, not yet reduced

    static func parse(_ input: String) -> NumberFacts? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard text.range(of: "^[0-9]{1,12}(\\.[0-9]{1,9})?$", options: .regularExpression) != nil else { return nil }
        let parts = text.split(separator: ".")
        if parts.count == 1 {
            guard let n = Int(text), n >= 2 else { return nil }
            return NumberFacts(text: String(n), whole: n, fraction: nil)
        }
        // Noughts on the end are no part of the fraction: 2.50 is 5/2.
        var digits = String(parts[1])
        while digits.hasSuffix("0") { digits.removeLast() }
        guard !digits.isEmpty, parts[0].count + digits.count <= 15, let top = Int(parts[0] + digits) else { return nil }
        let bottom = (0..<digits.count).reduce(1) { n, _ in n * 10 }
        return NumberFacts(text: text, whole: nil, fraction: (top, bottom))
    }

    // The primes of n with how many times each divides it, smallest first.
    static func factors(_ n: Int) -> [(prime: Int, power: Int)] {
        var out: [(prime: Int, power: Int)] = []
        var rest = n, p = 2
        while p * p <= rest {
            var power = 0
            while rest % p == 0 {
                rest /= p
                power += 1
            }
            if power > 0 { out.append((p, power)) }
            p += p == 2 ? 1 : 2
        }
        if rest > 1 { out.append((rest, 1)) }
        return out
    }

    private static func product(_ factors: [(prime: Int, power: Int)]) -> Math {
        var parts: [Math] = []
        for (i, f) in factors.enumerated() {
            if i > 0 { parts.append(t("·")) }
            parts.append(f.power == 1 ? t("\(f.prime)") : .power(t("\(f.prime)"), t("\(f.power)")))
        }
        return .row(parts)
    }

    // 144 = 12², 1296 = 6⁴: the highest power the whole number is, where it is one and its root
    // is not simply a prime, which the factors have said already.
    private static func perfectPower(_ factors: [(prime: Int, power: Int)]) -> Math? {
        let power = factors.reduce(0) { gcd($0, $1.power) }
        guard power >= 2, factors.count >= 2 else { return nil }
        let root = factors.reduce(1) { root, f in root * (0..<(f.power / power)).reduce(1) { n, _ in n * f.prime } }
        return row(t("= "), .power(t("\(root)"), t("\(power)")))
    }

    // The lines of the answer: the factors and any perfect power, "97 is prime", or the fraction.
    private var lines: [Math] {
        if let n = whole {
            let factors = NumberFacts.factors(n)
            if factors.count == 1, factors[0].power == 1 { return [t("\(n) is prime")] }
            return [row(t("\(n) = "), NumberFacts.product(factors))] + [NumberFacts.perfectPower(factors)].compactMap { $0 }
        }
        guard let (top, bottom) = fraction else { return [] }
        return [row(t("\(text) = "), fractionMath(top, bottom))]
    }

    var solution: Solution {
        let lines = self.lines.map(\.plain)
        return Solution(exact: lines[0], approx: lines.count > 1 ? lines[1] : nil)
    }

    var details: Details {
        var d = Details(name: "", equation: t(text), steps: [], solutions: lines, note: nil, f: { _ in .nan }, roots: [])
        if let n = whole {
            let factors = NumberFacts.factors(n)
            if factors.count == 1, factors[0].power == 1 {
                let limit = Int(Double(n).squareRoot())
                d.steps = [Step(label: "Testing for divisors", math: nil,
                                note: limit < 2 ? "\(n) has no divisor but 1 and itself; it is therefore prime."
                                                : "\(n) is divisible by no prime up to its square root, \(decimal(Double(n).squareRoot())); it is therefore prime.")]
                return d
            }
            // Each prime is divided out as often as it will go, leaving a smaller number for the next.
            var rest = n
            for (i, f) in factors.enumerated() {
                let after = rest / (0..<f.power).reduce(1) { m, _ in m * f.prime }
                if i == factors.count - 1, f.power == 1, factors.count > 1 { break }   // what is left is the last prime
                let found = NumberFacts.product([f])
                d.steps.append(Step(label: f.power == 1 ? "Dividing by \(f.prime)" : "Dividing by \(f.prime) repeatedly",
                                    math: after == 1 ? row(t("\(rest) = "), found) : row(t("\(rest) = "), found, t("·\(after)"))))
                rest = after
            }
            if factors.count > 1 { d.steps.append(Step(label: "Hence", math: row(t("\(n) = "), NumberFacts.product(factors)))) }
            return d
        }
        guard let (top, bottom) = fraction else { return d }
        d.steps.append(Step(label: "Writing as a fraction", math: row(t("\(text) = "), .fraction(t("\(top)"), t("\(bottom)")))))
        let common = gcd(top, bottom)
        if common > 1 { d.steps.append(Step(label: "Dividing through by \(common)", math: row(t("\(text) = "), fractionMath(top, bottom)))) }
        return d
    }
}
