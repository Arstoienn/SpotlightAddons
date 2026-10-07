import Foundation

// A set of numbers as intervals, the answer to an inequality: x < −2 or x > 2. Two sets can be
// taken together (||) or only what they share (&&, or a chain, 1 < x < 5).
struct Bound {
    var value: Double
    var exact: String      // −√2, or 1/2
    var decimal: String    // −1.41421
}

struct Interval {
    var lower: Bound?, lowerClosed = false     // nil: no end to it
    var upper: Bound?, upperClosed = false
}

struct IntervalSet {
    var items: [Interval]

    static let everything = IntervalSet(items: [Interval()])
    static let nothing = IntervalSet(items: [])

    private static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(1, abs(a), abs(b)) }

    // Sorted, with the intervals that touch or overlap made one.
    var normalised: IntervalSet {
        let sorted = items.sorted { ($0.lower?.value ?? -.infinity) < ($1.lower?.value ?? -.infinity) }
        var out: [Interval] = []
        for item in sorted {
            guard var last = out.last else { out.append(item); continue }
            let gapIsNothing: Bool
            switch (last.upper, item.lower) {
            case (nil, _), (_, nil): gapIsNothing = true
            case (let hi?, let lo?):
                gapIsNothing = hi.value > lo.value && !IntervalSet.same(hi.value, lo.value) || (IntervalSet.same(hi.value, lo.value) && (last.upperClosed || item.lowerClosed))
            }
            if gapIsNothing {
                // Starting at the same place, the one that includes it decides.
                if let a = last.lower, let b = item.lower, IntervalSet.same(a.value, b.value) { last.lowerClosed = last.lowerClosed || item.lowerClosed }
                // The upper end is the higher of the two.
                if let hi = item.upper, let lastHigh = last.upper {
                    if hi.value > lastHigh.value && !IntervalSet.same(hi.value, lastHigh.value) { last.upper = item.upper; last.upperClosed = item.upperClosed }
                    else if IntervalSet.same(hi.value, lastHigh.value) { last.upperClosed = last.upperClosed || item.upperClosed }
                } else if item.upper == nil { last.upper = nil; last.upperClosed = false }
                out[out.count - 1] = last
            } else {
                out.append(item)
            }
        }
        return IntervalSet(items: out)
    }

    func intersection(_ other: IntervalSet) -> IntervalSet {
        var out: [Interval] = []
        for a in items {
            for b in other.items {
                var r = Interval()
                // The higher of the two lower ends, the lower of the two upper.
                switch (a.lower, b.lower) {
                case (nil, nil): break
                case (let x?, nil): r.lower = x; r.lowerClosed = a.lowerClosed
                case (nil, let y?): r.lower = y; r.lowerClosed = b.lowerClosed
                case (let x?, let y?):
                    if IntervalSet.same(x.value, y.value) { r.lower = x; r.lowerClosed = a.lowerClosed && b.lowerClosed }
                    else if x.value > y.value { r.lower = x; r.lowerClosed = a.lowerClosed } else { r.lower = y; r.lowerClosed = b.lowerClosed }
                }
                switch (a.upper, b.upper) {
                case (nil, nil): break
                case (let x?, nil): r.upper = x; r.upperClosed = a.upperClosed
                case (nil, let y?): r.upper = y; r.upperClosed = b.upperClosed
                case (let x?, let y?):
                    if IntervalSet.same(x.value, y.value) { r.upper = x; r.upperClosed = a.upperClosed && b.upperClosed }
                    else if x.value < y.value { r.upper = x; r.upperClosed = a.upperClosed } else { r.upper = y; r.upperClosed = b.upperClosed }
                }
                if let lo = r.lower, let hi = r.upper {
                    if lo.value > hi.value && !IntervalSet.same(lo.value, hi.value) { continue }
                    if IntervalSet.same(lo.value, hi.value), !(r.lowerClosed && r.upperClosed) { continue }
                }
                out.append(r)
            }
        }
        return IntervalSet(items: out).normalised
    }

    func union(_ other: IntervalSet) -> IntervalSet { IntervalSet(items: items + other.items).normalised }

    // x < −2 or x > 2; −2 ≤ x ≤ 2; x ≠ 1, 2; x = 0; x ∈ ℝ; No solution.
    func text(_ name: String, exactly: Bool = true) -> String {
        let set = normalised
        if set.items.isEmpty { return "No solution" }
        func label(_ b: Bound) -> String { exactly ? b.exact : b.decimal }
        if set.items.count == 1, set.items[0].lower == nil, set.items[0].upper == nil { return "\(name) ∈ ℝ" }
        // All of the line but some points: x ≠ 2, −2.
        if set.items.count >= 2, set.items.first?.lower == nil, set.items.last?.upper == nil {
            var points: [String] = []
            var onlyPoints = true
            for (a, b) in zip(set.items, set.items.dropFirst()) {
                if let hi = a.upper, let lo = b.lower, IntervalSet.same(hi.value, lo.value), !a.upperClosed, !b.lowerClosed { points.append(label(hi)) } else { onlyPoints = false }
            }
            if onlyPoints { return "\(name) ≠ " + points.joined(separator: ", ") }
        }
        return set.items.map { item in
            switch (item.lower, item.upper) {
            case (nil, nil): return "\(name) ∈ ℝ"
            case (nil, let u?): return "\(name) \(item.upperClosed ? "≤" : "<") \(label(u))"
            case (let l?, nil): return "\(name) \(item.lowerClosed ? "≥" : ">") \(label(l))"
            case (let l?, let u?):
                if IntervalSet.same(l.value, u.value), item.lowerClosed, item.upperClosed { return "\(name) = \(label(l))" }
                return "\(label(l)) \(item.lowerClosed ? "≤" : "<") \(name) \(item.upperClosed ? "≤" : "<") \(label(u))"
            }
        }.joined(separator: " or ")
    }
}
