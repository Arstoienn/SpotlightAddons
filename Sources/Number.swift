import Foundation

// A number typed by itself has nothing to solve or work out, but something can still be said of
// it: a whole number is the product of its primes, 2048 = 2¹¹, or is one; one below nought is −1
// times that, −12 = −1·2²·3; 0, 1 and −1 are neither prime nor a product of primes; and a decimal
// is a fraction, 0.375 = 3/8.
struct NumberFacts {
    var text: String          // as typed, with its minus written −
    var whole: Int?           // 2048, or −12
    var fraction: (Int, Int)? // 0.375 as 375 over 1000, not yet reduced

    static func parse(_ input: String) -> NumberFacts? {
        let typed = input.trimmingCharacters(in: .whitespaces)
        guard typed.range(of: "^[-−]?[0-9]{1,12}(\\.[0-9]{1,9})?$", options: .regularExpression) != nil else { return nil }
        let negative = typed.hasPrefix("-") || typed.hasPrefix("−")
        let digits = negative ? String(typed.dropFirst()) : typed
        let parts = digits.split(separator: ".")
        if parts.count == 1 {
            guard let n = Int(digits) else { return nil }
            return NumberFacts(text: (negative && n != 0 ? "−" : "") + String(n), whole: negative ? -n : n, fraction: nil)
        }
        // Noughts on the end are no part of the fraction: 2.50 is 5/2.
        var places = String(parts[1])
        while places.hasSuffix("0") { places.removeLast() }
        guard !places.isEmpty, parts[0].count + places.count <= 15, let top = Int(parts[0] + places) else { return nil }
        let bottom = (0..<places.count).reduce(1) { n, _ in n * 10 }
        return NumberFacts(text: (negative ? "−" : "") + digits, whole: nil, fraction: (negative ? -top : top, bottom))
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

    // 0, 1 and −1: no prime, and no product of primes. What is said of each, and why.
    private var neither: (line: String, why: String, working: String)? {
        switch whole {
        case 0: return ("0 is neither prime nor composite", "Every whole number divides it",
                        "Every whole number divides 0, whereas a prime has exactly two divisors; nor is 0 a product of primes.")
        case 1: return ("1 is neither prime nor composite", "Its only divisor is 1",
                        "1 has one divisor, itself, whereas a prime has exactly two; nor is 1 a product of primes.")
        case -1: return ("−1 is neither prime nor composite", "Its only divisors are 1 and −1",
                         "−1 is divided only by 1 and −1, which divide every whole number; nor is it −1 times a product of primes.")
        default: return nil
        }
    }

    // n, or −1 times it below nought: −12 = −1·2²·3.
    private func signed(_ m: Math) -> Math { (whole ?? 0) < 0 ? row(t("−1·"), m) : m }

    // The lines of the answer: the factors and any perfect power, "97 is prime", or the fraction.
    private var lines: [Math] {
        if let neither { return [t(neither.line)] }
        if let n = whole {
            let factors = NumberFacts.factors(abs(n))
            if n > 0, factors.count == 1, factors[0].power == 1 { return [t("\(n) is prime")] }
            let power = n > 0 ? NumberFacts.perfectPower(factors) : nil
            return [row(t("\(text) = "), signed(NumberFacts.product(factors)))] + [power].compactMap { $0 }
        }
        guard let (top, bottom) = fraction else { return [] }
        return [row(t("\(text) = "), fractionMath(top, bottom))]
    }

    var solution: Solution {
        let lines = self.lines.map(\.plain)
        return Solution(exact: lines[0], approx: neither?.why ?? (lines.count > 1 ? lines[1] : nil))
    }

    var details: Details {
        var d = Details(name: "", equation: t(text), steps: [], solutions: lines, note: nil, f: { _ in .nan }, roots: [])
        if let neither {
            d.steps = [Step(label: "Testing for divisors", math: nil, note: neither.working)]
            return d
        }
        if let n = whole {
            let m = abs(n)
            let factors = NumberFacts.factors(m)
            // Below nought, −1 is taken out first, and what is left is worked as any whole number.
            if n < 0 { d.steps.append(Step(label: "Taking out −1", math: row(t("\(text) = "), t("−1·\(m)")))) }
            if factors.count == 1, factors[0].power == 1 {
                let root = Double(m).squareRoot()
                d.steps.append(Step(label: "Testing for divisors", math: nil,
                                    note: root < 2 ? "\(m) has no divisor but 1 and itself; it is therefore prime."
                                                   : "\(m) is divisible by no prime up to its square root, \(decimal(root)); it is therefore prime."))
                return d
            }
            // Each prime is divided out as often as it will go, leaving a smaller number for the next.
            var rest = m
            for (i, f) in factors.enumerated() {
                let after = rest / (0..<f.power).reduce(1) { k, _ in k * f.prime }
                if i == factors.count - 1, f.power == 1, factors.count > 1 { break }   // what is left is the last prime
                let found = NumberFacts.product([f])
                d.steps.append(Step(label: f.power == 1 ? "Dividing by \(f.prime)" : "Dividing by \(f.prime) repeatedly",
                                    math: after == 1 ? row(t("\(rest) = "), found) : row(t("\(rest) = "), found, t("·\(after)"))))
                rest = after
            }
            if factors.count > 1 || n < 0 { d.steps.append(Step(label: "Hence", math: row(t("\(text) = "), signed(NumberFacts.product(factors))))) }
            return d
        }
        guard let (top, bottom) = fraction else { return d }
        let unreduced: Math = .fraction(t("\(abs(top))"), t("\(bottom)"))
        d.steps.append(Step(label: "Writing as a fraction", math: row(t("\(text) = "), top < 0 ? row(t("−"), unreduced) : unreduced)))
        let common = gcd(abs(top), bottom)
        if common > 1 { d.steps.append(Step(label: "Dividing through by \(common)", math: row(t("\(text) = "), fractionMath(top, bottom)))) }
        return d
    }
}
