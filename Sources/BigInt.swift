import Foundation

// Whole numbers of any size, for 2^100 and 30!: written out in full where the machine's double
// would give only sixteen figures.
struct BigInt {
    private var limbs: [UInt32]       // base 10⁹, least first; no zeros at the end
    var negative = false

    private static let base: UInt64 = 1_000_000_000

    init(_ value: Int) {
        negative = value < 0
        var m = value.magnitude
        limbs = []
        while m > 0 { limbs.append(UInt32(m % UInt(BigInt.base))); m /= UInt(BigInt.base) }
    }

    private init(limbs: [UInt32], negative: Bool) {
        var l = limbs
        while l.last == 0 { l.removeLast() }
        self.limbs = l
        self.negative = l.isEmpty ? false : negative
    }

    var isZero: Bool { limbs.isEmpty }

    var digitCount: Int { limbs.isEmpty ? 1 : (limbs.count - 1) * 9 + String(limbs.last!).count }

    var description: String {
        guard let top = limbs.last else { return "0" }
        var s = String(top)
        for limb in limbs.dropLast().reversed() { s += String(repeating: "0", count: 9 - String(limb).count) + String(limb) }
        return (negative ? "−" : "") + s
    }

    private static func compare(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
        return 0
    }

    private static func add(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = [], carry: UInt64 = 0
        for i in 0..<max(a.count, b.count) {
            let s = UInt64(i < a.count ? a[i] : 0) + UInt64(i < b.count ? b[i] : 0) + carry
            out.append(UInt32(s % base))
            carry = s / base
        }
        if carry > 0 { out.append(UInt32(carry)) }
        return out
    }

    // a − b for a ≥ b.
    private static func subtract(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = [], borrow: Int64 = 0
        for i in 0..<a.count {
            var d = Int64(a[i]) - Int64(i < b.count ? b[i] : 0) - borrow
            if d < 0 { d += Int64(base); borrow = 1 } else { borrow = 0 }
            out.append(UInt32(d))
        }
        return out
    }

    static func + (a: BigInt, b: BigInt) -> BigInt {
        if a.negative == b.negative { return BigInt(limbs: add(a.limbs, b.limbs), negative: a.negative) }
        switch compare(a.limbs, b.limbs) {
        case 0: return BigInt(0)
        case 1: return BigInt(limbs: subtract(a.limbs, b.limbs), negative: a.negative)
        default: return BigInt(limbs: subtract(b.limbs, a.limbs), negative: b.negative)
        }
    }

    static prefix func - (a: BigInt) -> BigInt { BigInt(limbs: a.limbs, negative: !a.negative) }
    static func - (a: BigInt, b: BigInt) -> BigInt { a + (-b) }

    static func * (a: BigInt, b: BigInt) -> BigInt {
        guard !a.isZero, !b.isZero else { return BigInt(0) }
        var out = [UInt64](repeating: 0, count: a.limbs.count + b.limbs.count + 1)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                let cur = out[i + j] + UInt64(a.limbs[i]) * UInt64(b.limbs[j]) + carry
                out[i + j] = cur % base
                carry = cur / base
            }
            var k = i + b.limbs.count
            while carry > 0 { let cur = out[k] + carry; out[k] = cur % base; carry = cur / base; k += 1 }
        }
        return BigInt(limbs: out.map { UInt32($0) }, negative: a.negative != b.negative)
    }

    func power(_ n: Int) -> BigInt {
        var result = BigInt(1), base = self, n = n
        while n > 0 {
            if n & 1 == 1 { result = result * base }
            n >>= 1
            if n > 0 { base = base * base }
        }
        return result
    }

    // Exactly divided by a whole number that is small, or nil where it does not go.
    func dividedExactly(by d: Int) -> BigInt? {
        guard d != 0, d.magnitude < UInt(BigInt.base) else { return nil }
        var out = [UInt32](repeating: 0, count: limbs.count), remainder: UInt64 = 0
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            let cur = remainder * BigInt.base + UInt64(limbs[i])
            out[i] = UInt32(cur / UInt64(d.magnitude))
            remainder = cur % UInt64(d.magnitude)
        }
        guard remainder == 0 else { return nil }
        return BigInt(limbs: out, negative: negative != (d < 0))
    }
}

extension Expr {
    // The value as a whole number, in full, where every part of it is one and the work is only
    // adding, taking away, multiplying, raising to a power and the factorial; nil otherwise, or
    // where it would be too long to write out.
    var exactInteger: BigInt? {
        func size(_ b: BigInt) -> Bool { b.digitCount <= 400 }
        switch self {
        case .num(let v):
            guard v == v.rounded(), abs(v) < 9e15 else { return nil }
            return BigInt(Int(v))
        case .neg(let a): return a.exactInteger.map { -$0 }
        case .op(let o, let a, let b):
            guard let x = a.exactInteger, let y = b.exactInteger else { return nil }
            switch o {
            case "+": return x + y
            case "-": return x - y
            case "*": return size(x) && size(y) ? x * y : nil
            case "/":
                guard let d = Int(y.description.replacingOccurrences(of: "−", with: "-")) else { return nil }
                return x.dividedExactly(by: d)
            case "^":
                guard !y.negative, y.digitCount <= 5, let n = Int(y.description), n <= 100_000,
                      x.digitCount * n <= 400 else { return nil }
                return x.power(n)
            default: return nil
            }
        case .call("fact", let a):
            guard let n = a.exactInteger, !n.negative, n.digitCount <= 4, let k = Int(n.description), k <= 400 else { return nil }
            var r = BigInt(1)
            if k >= 2 { for i in 2...k { r = r * BigInt(i) } }
            return r
        default: return nil
        }
    }
}
