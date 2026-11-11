import Foundation

// A colour, written in any of the ways it is written: #FF5733, rgb(255, 87, 51), hsl(11, 100%, 60%),
// hsb( ), cmyk( ), a name of CSS, red, or in a wider gamut, color(display-p3 1 0 0), color(rec2020 …),
// lab( ), lch( ), oklab( ), oklch( ), or by its CIE coordinates, xyY(0.64, 0.33, 0.2126). The card
// shows it, and gives it in another of those ways, or in the one asked for, #FF5733 to hsl; the working
// converts it into each, step by step, finds the nearest named colour and its contrast with white and
// with black. Colours are reckoned with as light, channel by channel from 0 to 255: red + blue, white −
// red, red × 2, red ÷ 2, red × blue (as through two filters); a colour divided by a colour is refused.
// mix(a, b[, share]) mixes two as Sass's mix( ) does; gradient(a, b, n) and interpolate(a, b, t) go
// evenly between; deltaE(a, b) is how far apart they look; contrast(a, b) is the ratio of WCAG 2.

// A colour as sRGB writes it, each channel from 0 to 1 on sRGB's curve; a colour outside what sRGB
// can show has a channel below 0 or above 1, and is clipped only when it is written as hex or rgb.
struct RGBA: Equatable {
    var r: Double, g: Double, b: Double
    var a: Double = 1

    // sRGB's curve, both ways, kept odd so that a channel below 0 goes through it too.
    static func linear(_ c: Double) -> Double { c < 0 ? -linear(-c) : c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func encode(_ c: Double) -> Double { c < 0 ? -encode(-c) : c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    init(r: Double, g: Double, b: Double, a: Double = 1) { (self.r, self.g, self.b, self.a) = (r, g, b, a) }

    // From CIE XYZ under D65, Y of white 1.
    init(xyz: (Double, Double, Double), a: Double = 1) {
        let (lr, lg, lb) = Gamut.srgb.fromXYZ(xyz)
        self.init(r: RGBA.encode(lr), g: RGBA.encode(lg), b: RGBA.encode(lb), a: a)
    }

    // From x, y and the luminance Y.
    init(x: Double, y: Double, Y: Double, a: Double = 1) {
        self.init(xyz: y <= 0 ? (0, 0, 0) : (x * Y / y, Y, (1 - x - y) * Y / y), a: a)
    }

    var xyz: (Double, Double, Double) { Gamut.srgb.toXYZ((RGBA.linear(r), RGBA.linear(g), RGBA.linear(b))) }

    // x and y of CIE 1931, and Y. Black, which has no chromaticity, is put at the white point, as a
    // grey of any lightness is.
    var xyY: (Double, Double, Double) {
        let (x, y, z) = xyz, total = x + y + z
        return total < 1e-9 ? (0.3127, 0.3290, 0) : (x / total, y / total, y)
    }
    var xy: (Double, Double) { (xyY.0, xyY.1) }

    var clamped: RGBA { RGBA(r: min(1, max(0, r)), g: min(1, max(0, g)), b: min(1, max(0, b)), a: a) }
    var inSRGB: Bool { [r, g, b].allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 } }
    func within(_ gamut: Gamut) -> Bool {
        let (p, q, s) = gamut.fromXYZ(xyz)
        return [p, q, s].allSatisfy { $0 >= -1e-4 && $0 <= 1 + 1e-4 }
    }
    // The smallest of the three gamuts it lies in.
    var gamut: Gamut? { Gamut.allCases.first { within($0) } }

    var bytes: (Int, Int, Int) { let c = clamped; return (Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded())) }

    // The relative luminance of WCAG 2, of the colour as a screen shows it.
    var luminance: Double { clamped.xyz.1 }

    // CIELAB as CSS has it, under D50: XYZ adapted from D65 by Bradford's method.
    var lab: (Double, Double, Double) {
        let (x, y, z) = xyz
        let d50 = (1.0479298209 * x + 0.0229468970 * y - 0.0501922295 * z,
                   0.0296278156 * x + 0.9904344268 * y - 0.0170738250 * z,
                   -0.0092430582 * x + 0.0150551448 * y + 0.7518742899 * z)
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let (fx, fy, fz) = (f(d50.0 / 0.96422), f(d50.1), f(d50.2 / 0.82521))
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    init(lab: (Double, Double, Double), a: Double = 1) {
        let (l, aa, bb) = lab
        let fy = (l + 16) / 116, fx = fy + aa / 500, fz = fy - bb / 200
        let (k, e) = (24389.0 / 27, 216.0 / 24389)
        func inverse(_ t: Double) -> Double { t * t * t > e ? t * t * t : (116 * t - 16) / k }
        let d50 = (0.96422 * inverse(fx), l > k * e ? fy * fy * fy : l / k, 0.82521 * inverse(fz))
        let (x, y, z) = d50
        self.init(xyz: (0.9554734528 * x - 0.0230984546 * y + 0.0632593086 * z,
                        -0.0283697093 * x + 1.0099955524 * y + 0.0210413990 * z,
                        0.0123140017 * x - 0.0205076964 * y + 1.3303659366 * z), a: a)
    }

    // OKLab, by way of the cone responses.
    var oklab: (Double, Double, Double) {
        let (lr, lg, lb) = (RGBA.linear(r), RGBA.linear(g), RGBA.linear(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    init(oklab: (Double, Double, Double), a: Double = 1) {
        let (L, A, B) = oklab
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.2914855480 * B, 3)
        self.init(r: RGBA.encode(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                  g: RGBA.encode(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                  b: RGBA.encode(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), a: a)
    }

    // ΔE of CIE 1976: the straight distance between them in CIELAB.
    func distance(to other: RGBA) -> Double {
        let (l1, a1, b1) = lab, (l2, a2, b2) = other.lab
        return ((l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2)).squareRoot()
    }

    // Polar forms: the chroma and the hue, in degrees.
    static func polar(_ a: Double, _ b: Double) -> (Double, Double) {
        var h = atan2(b, a) * 180 / .pi
        if h < 0 { h += 360 }
        return ((a * a + b * b).squareRoot(), h)
    }
}

// The gamuts a screen may show: their primaries on the diagram, and their channels from CIE XYZ.
enum Gamut: String, CaseIterable {
    case srgb = "sRGB", p3 = "Display P3", rec2020 = "Rec. 2020"

    var primaries: [(Double, Double)] {
        switch self {
        case .srgb: [(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)]
        case .p3: [(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)]
        case .rec2020: [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]
        }
    }

    private var toMatrix: [Double] {
        switch self {
        case .srgb: [0.4123907993, 0.3575843394, 0.1804807884, 0.2126390059, 0.7151686788, 0.0721923154, 0.0193308187, 0.1191947798, 0.9505321522]
        case .p3: [0.4865709486, 0.2656676932, 0.1982172852, 0.2289745641, 0.6917385218, 0.0792869141, 0, 0.0451133819, 1.0439443689]
        case .rec2020: [0.6369580483, 0.1446169036, 0.1688809752, 0.2627002120, 0.6779980715, 0.0593017165, 0, 0.0280726930, 1.0609850577]
        }
    }

    private var fromMatrix: [Double] {
        switch self {
        case .srgb: [3.2409699419, -1.5373831776, -0.4986107603, -0.9692436363, 1.8759675015, 0.0415550574, 0.0556300797, -0.2039769589, 1.0569715142]
        case .p3: [2.4934969119, -0.9313836179, -0.4027107845, -0.8294889696, 1.7626640603, 0.0236246858, 0.0358458302, -0.0761723893, 0.9568845240]
        case .rec2020: [1.7166511880, -0.3556707838, -0.2533662814, -0.6666843518, 1.6164812366, 0.0157685458, 0.0176398574, -0.0427706133, 0.9421031212]
        }
    }

    private static func apply(_ m: [Double], _ v: (Double, Double, Double)) -> (Double, Double, Double) {
        (m[0] * v.0 + m[1] * v.1 + m[2] * v.2, m[3] * v.0 + m[4] * v.1 + m[5] * v.2, m[6] * v.0 + m[7] * v.1 + m[8] * v.2)
    }

    // Linear channels to XYZ, and back.
    func toXYZ(_ linear: (Double, Double, Double)) -> (Double, Double, Double) { Gamut.apply(toMatrix, linear) }
    func fromXYZ(_ xyz: (Double, Double, Double)) -> (Double, Double, Double) { Gamut.apply(fromMatrix, xyz) }

    // The curve each puts its channels on: sRGB's for sRGB and Display P3, Rec. 2020's own.
    func encode(_ c: Double) -> Double {
        guard self == .rec2020 else { return RGBA.encode(c) }
        let (alpha, beta) = (1.09929682680944, 0.018053968510807)
        if c < 0 { return -encode(-c) }
        return c < beta ? 4.5 * c : alpha * pow(c, 0.45) - (alpha - 1)
    }
    func decode(_ c: Double) -> Double {
        guard self == .rec2020 else { return RGBA.linear(c) }
        let (alpha, beta) = (1.09929682680944, 0.018053968510807)
        if c < 0 { return -decode(-c) }
        return c < beta * 4.5 ? c / 4.5 : pow((c + alpha - 1) / alpha, 1 / 0.45)
    }

    // A colour's channels in this gamut, on its curve.
    func channels(_ x: RGBA) -> (Double, Double, Double) {
        let (p, q, s) = fromXYZ(x.xyz)
        return (encode(p), encode(q), encode(s))
    }
}

// What the card shows on its left in place of a sign: the colour, or text in one colour on another.
enum Swatch: Equatable {
    case solid(RGBA)
    case text(RGBA, on: RGBA)          // the first colour as text on the second
    case pair(RGBA, RGBA)              // two colours side by side
    case gradient([RGBA])
}

// Where colours lie on the CIE 1931 chromaticity diagram, in place of the working's graph. The
// colours typed are its inputs, which may be dragged about the diagram, and a mixture's share, which
// a slider sets; from them, every time, the marks: each colour at its x and y, with lines from the
// colours added or multiplied to what they make, or the path a mixture goes along with the result on it.
struct Chromaticity {
    struct Mark {
        var colour: RGBA
        var label: String
        var result = false
        var input: Int? = nil     // which input it is, where it may be dragged
        var small = false         // a stop of a gradient
    }
    struct Scene {
        var marks: [Mark]
        var lines: [(Int, Int)] = []
        var path: [RGBA] = []          // a mixture's colours, from the first to the second
        var onPath: Int? = nil         // the mark that moves along it with the share
    }
    var inputs: [RGBA]
    var share: Double?                 // the first colour's share in a mixture, where there is one
    var make: ([RGBA], Double) -> Scene
}

struct Colour {
    enum Format: String, CaseIterable { case hex, rgb, hsl, hsb, cmyk, name, p3, rec2020, lab, lch, oklab, oklch, xyy }
    // The ways listed under Solutions.
    static let listed: [Format] = [.hex, .rgb, .hsl, .hsb, .cmyk, .lab, .oklch, .p3, .xyy]

    // Light reckoned with: the colours typed, numbers, and what is done to them.
    indirect enum Node { case colour(Int), number(Double), op(Character, Node, Node) }
    enum Value { case colour(RGBA), number(Double) }
    struct Operation {
        var op: Character
        var left: Value, right: Value
        var result: RGBA
        var leftMark: Int?, rightMark: Int?     // the marks of the colours it was made from
        var text: String                         // A + B
    }

    enum Kind {
        case one(RGBA, typed: Format)
        case mix(RGBA, RGBA, weight: Double)          // the weight is the first colour's share
        case arithmetic(Node, inputs: [RGBA])
        case distance(RGBA, RGBA)
        case gradient(RGBA, RGBA, count: Int)
        case contrast(RGBA, RGBA)
        case invalid(String)                          // what is wrong with what was typed
    }

    var kind: Kind
    var asked: Format?
    var typed: String

    struct Refusal: Error { let reason: String }

    // MARK: Reading

    static func parse(_ input: String) -> Colour? {
        let text = input.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        // mix(a, b[, share]), interpolate(a, b, t), gradient(a, b[, n]), deltaE(a, b) and contrast(a, b).
        let functions = ["mix", "interpolate", "lerp", "gradient", "deltae", "δe", "distance", "contrast"]
        if let word = functions.first(where: { lower.hasPrefix($0 + "(") }), lower.hasSuffix(")") {
            let parts = Taylor.topLevel(String(text.dropFirst(word.count + 1).dropLast())).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 || parts.count == 3 else { return nil }
            guard let first = read(parts[0]), let second = read(parts[1]) else { return nil }
            if case .failure(let why) = first { return Colour(kind: .invalid(why.reason), typed: text) }
            if case .failure(let why) = second { return Colour(kind: .invalid(why.reason), typed: text) }
            guard case .success(let a) = first, case .success(let b) = second else { return nil }
            let third = parts.count == 3 ? parts[2] : nil
            switch word {
            case "mix", "interpolate", "lerp":
                var share = 0.5
                if let third {
                    guard let given = amount(third, percentOf: 1) else { return nil }
                    guard (0...1).contains(given) else { return Colour(kind: .invalid("The share is from 0% to 100%, or 0 to 1."), typed: text) }
                    // mix( ) is given the first colour's share, as Sass has it; interpolate( ) how far along to the second.
                    share = word == "mix" ? given : 1 - given
                }
                return Colour(kind: .mix(a.0, b.0, weight: share), typed: text)
            case "gradient":
                var count = 5
                if let third {
                    guard let n = Int(third) else { return nil }
                    guard (2...100).contains(n) else { return Colour(kind: .invalid("A gradient has from 2 to 100 colours."), typed: text) }
                    count = n
                }
                return Colour(kind: .gradient(a.0, b.0, count: count), typed: text)
            case "contrast":
                return third == nil ? Colour(kind: .contrast(a.0, b.0), typed: text) : nil
            default:
                return third == nil ? Colour(kind: .distance(a.0, b.0), typed: text) : nil
            }
        }
        // red + blue, white − red, red × 2, red ÷ 2, red × blue: light reckoned with, channel by channel.
        if let reckoned = arithmetic(text) { return reckoned }
        // "… to hsl", "… in hex", "… as cmyk": the way the answer is to be written.
        var body = text, asked: Format?
        let ways = "hex|rgba?|hsla?|hsb|hsv|cmyk|name|display-p3|p3|rec2020|lab|lch|oklab|oklch|xyy"
        if let m = lower.range(of: "\\s+(to|in|as)\\s+(\(ways))$", options: .regularExpression) {
            let word = lower[m].split(separator: " ").last.map(String.init) ?? ""
            asked = ["rgba": .rgb, "hsla": .hsl, "hsv": .hsb, "display-p3": .p3].first { $0.key == word }?.value ?? Format(rawValue: word)
            body = String(text[..<m.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        // "colour tomato", "color of #FF5733".
        if let m = body.lowercased().range(of: "^colou?r(\\s+of)?\\s+", options: .regularExpression) { body = String(body[m.upperBound...]) }
        guard let found = read(body) else { return nil }
        switch found {
        case .failure(let why): return Colour(kind: .invalid(why.reason), asked: asked, typed: text)
        case .success(let (colour, format)): return Colour(kind: .one(colour, typed: format), asked: asked, typed: text)
        }
    }

    // An expression of colours and numbers: + and − between colours, × and ÷ by numbers or × between
    // colours, in brackets or not. nil unless it has an operation and a colour in it.
    private static func arithmetic(_ text: String) -> Colour? {
        let chars = Array(text)
        var at = 0, inputs: [RGBA] = [], refusal: String?
        func skip() { while at < chars.count, chars[at] == " " { at += 1 } }
        func expression() -> Node? {
            guard var left = term() else { return nil }
            while true {
                skip()
                guard at < chars.count, "+-−".contains(chars[at]) else { return left }
                let op: Character = chars[at] == "+" ? "+" : "−"
                at += 1
                guard let right = term() else { return nil }
                left = .op(op, left, right)
            }
        }
        func term() -> Node? {
            guard var left = factor() else { return nil }
            while true {
                skip()
                guard at < chars.count, "*×·/÷".contains(chars[at]) else { return left }
                let op: Character = "/÷".contains(chars[at]) ? "÷" : "×"
                at += 1
                guard let right = factor() else { return nil }
                left = .op(op, left, right)
            }
        }
        func factor() -> Node? {
            skip()
            guard at < chars.count else { return nil }
            if chars[at] == "(" {
                at += 1
                guard let inside = expression() else { return nil }
                skip()
                guard at < chars.count, chars[at] == ")" else { return nil }
                at += 1
                return inside
            }
            // A colour or a number: up to an operation or a closing bracket outside its own brackets.
            var depth = 0, word = ""
            while at < chars.count {
                let c = chars[at]
                if depth == 0, "+-−*×·/÷)".contains(c) { break }
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                word.append(c)
                at += 1
            }
            word = word.trimmingCharacters(in: .whitespaces)
            // In an arithmetic expression tan is the trigonometric function awaiting its input.
            // The colour remains available by itself or as an explicit CSS value.
            if word.lowercased() == "tan" { return nil }
            if let v = Double(word) { return .number(v) }
            if word.hasSuffix("%"), let v = Double(word.dropLast()) { return .number(v / 100) }
            switch read(word) {
            case .success(let (colour, _))?:
                inputs.append(colour)
                return .colour(inputs.count - 1)
            case .failure(let why)?:
                refusal = why.reason
                return nil
            case nil: return nil
            }
        }
        let tree = expression()
        skip()
        if let refusal, chars.contains(where: { "+-−*×·/÷".contains($0) }) { return Colour(kind: .invalid(refusal), typed: text) }
        guard let tree, at == chars.count, !inputs.isEmpty, case .op = tree else { return nil }
        do {
            var operations: [Operation] = []
            guard case .colour = try evaluate(tree, inputs, &operations).0 else { return nil }
            return Colour(kind: .arithmetic(tree, inputs: inputs), typed: text)
        } catch let refusal as Refusal {
            return Colour(kind: .invalid(refusal.reason), typed: text)
        } catch {
            return nil
        }
    }

    // A, B, C: the colours typed, in order.
    static func letter(_ i: Int) -> String { i < 26 ? String(UnicodeScalar(65 + i)!) : "C\(i + 1)" }

    // What the expression comes to, every operation on the way written down with the marks it joins.
    // Each channel is kept between 0 and 255 after each operation, as a screen can show no more.
    static func evaluate(_ node: Node, _ inputs: [RGBA], _ operations: inout [Operation]) throws -> (Value, Int?, String) {
        switch node {
        case .colour(let i): return (.colour(inputs[i]), i, letter(i))
        case .number(let v): return (.number(v), nil, number(v, 4))
        case .op(let op, let l, let r):
            let (a, am, at) = try evaluate(l, inputs, &operations)
            let (b, bm, bt) = try evaluate(r, inputs, &operations)
            func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
            func each(_ x: RGBA, _ f: (Double) -> Double) -> RGBA { RGBA(r: clamp(f(x.clamped.r)), g: clamp(f(x.clamped.g)), b: clamp(f(x.clamped.b))) }
            let made: RGBA
            switch (op, a, b) {
            case (_, .number(let p), .number(let q)):
                let v: Double
                switch op { case "+": v = p + q; case "−": v = p - q; case "×": v = p * q
                default:
                    guard q != 0 else { throw Refusal(reason: "Division by nought.") }
                    v = p / q
                }
                return (.number(v), nil, number(v, 4))
            case ("+", .colour(let x), .colour(let y)):
                made = RGBA(r: clamp(x.clamped.r + y.clamped.r), g: clamp(x.clamped.g + y.clamped.g), b: clamp(x.clamped.b + y.clamped.b))
            case ("−", .colour(let x), .colour(let y)):
                made = RGBA(r: clamp(x.clamped.r - y.clamped.r), g: clamp(x.clamped.g - y.clamped.g), b: clamp(x.clamped.b - y.clamped.b))
            case ("×", .colour(let x), .colour(let y)):
                made = RGBA(r: x.clamped.r * y.clamped.r, g: x.clamped.g * y.clamped.g, b: x.clamped.b * y.clamped.b)
            case ("×", .colour(let x), .number(let k)), ("×", .number(let k), .colour(let x)):
                guard k >= 0 else { throw Refusal(reason: "Light cannot be scaled by a number below nought.") }
                made = each(x) { $0 * k }
            case ("÷", .colour(let x), .number(let k)):
                guard k != 0 else { throw Refusal(reason: "Division by nought.") }
                guard k > 0 else { throw Refusal(reason: "Light cannot be divided by a number below nought.") }
                made = each(x) { $0 / k }
            case ("÷", _, .colour):
                throw Refusal(reason: "Dividing by a colour has no meaning in light, and a channel of 0 would be division by nought.")
            default:
                throw Refusal(reason: "A number cannot be added to or taken from a colour; multiply or divide it instead: red × 2.")
            }
            let text = "\(at) \(op) \(bt)"
            operations.append(Operation(op: op, left: a, right: b, result: made, leftMark: am, rightMark: bm, text: text))
            return (.colour(made), inputs.count + operations.count - 1, operations.count == 1 && inputs.count <= 2 ? text : "(\(text))")
        }
    }

    // One colour, in whichever way it is written. nil for what is not a colour at all; a refusal for
    // one written wrongly, rgb(300, 0, 0).
    static func read(_ written: String) -> Result<(RGBA, Format), Refusal>? {
        let s = written.trimmingCharacters(in: .whitespaces).lowercased()
        if s.range(of: "^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$", options: .regularExpression) != nil {
            var digits = Array(s.dropFirst())
            if digits.count <= 4 { digits = digits.flatMap { [$0, $0] } }
            let values = stride(from: 0, to: digits.count, by: 2).map { Double(Int(String(digits[$0...$0 + 1]), radix: 16)!) / 255 }
            return .success((RGBA(r: values[0], g: values[1], b: values[2], a: values.count == 4 ? values[3] : 1), .hex))
        }
        if let hex = named[s.replacingOccurrences(of: " ", with: "")] { return read(hex).map { $0.map { ($0.0, Format.name) } } }
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let function = String(s[..<open]).trimmingCharacters(in: .whitespaces)
        let known = ["rgb", "rgba", "hsl", "hsla", "hsb", "hsba", "hsv", "hsva", "cmyk", "color", "lab", "lch", "oklab", "oklch", "xyy"]
        guard known.contains(function) else { return nil }
        // rgb(255, 87, 51), rgb(255 87 51 / 50%), and the alpha after a fourth comma.
        var inside = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
        var alphaText: String?
        if let slash = inside.firstIndex(of: "/") {
            alphaText = String(inside[inside.index(after: slash)...]).trimmingCharacters(in: .whitespaces)
            inside = String(inside[..<slash])
        }
        var parts = inside.contains(",") ? inside.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                         : inside.split(separator: " ").map(String.init)
        // color(display-p3 1 0 0): the space first.
        var space = ""
        if function == "color" {
            guard !parts.isEmpty else { return nil }
            space = parts.removeFirst()
        }
        let needed = function == "cmyk" ? 4 : 3
        if parts.count == needed + 1, alphaText == nil { alphaText = parts.removeLast() }
        guard parts.count == needed, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        var alpha = 1.0
        if let alphaText {
            guard let a = amount(alphaText, percentOf: 1) else { return nil }
            guard (0...1).contains(a) else { return .failure(Refusal(reason: "The alpha is from 0 to 1, or 0% to 100%.")) }
            alpha = a
        }
        switch function {
        case "rgb", "rgba":
            guard let values = Optional(parts.compactMap { amount($0, percentOf: 255) }), values.count == 3 else { return nil }
            guard values.allSatisfy({ (0...255).contains($0) }) else { return .failure(Refusal(reason: "Each channel of rgb( ) is from 0 to 255.")) }
            return .success((RGBA(r: values[0] / 255, g: values[1] / 255, b: values[2] / 255, a: alpha), .rgb))
        case "cmyk":
            let percents = parts.allSatisfy { $0.hasSuffix("%") } || parts.contains { (Double($0) ?? 0) > 1 }
            guard let values = Optional(parts.compactMap { amount($0, percentOf: 1, bare: percents ? 0.01 : 1) }), values.count == 4 else { return nil }
            guard values.allSatisfy({ (0...1).contains($0) }) else { return .failure(Refusal(reason: "Each of C, M, Y and K is from 0% to 100%.")) }
            let (c, m, y, k) = (values[0], values[1], values[2], values[3])
            return .success((RGBA(r: (1 - c) * (1 - k), g: (1 - m) * (1 - k), b: (1 - y) * (1 - k), a: alpha), .cmyk))
        case "color":
            let spaces: [String: (Gamut, Bool, Format)] = ["srgb": (.srgb, false, .rgb), "srgb-linear": (.srgb, true, .rgb),
                                                           "display-p3": (.p3, false, .p3), "rec2020": (.rec2020, false, .rec2020)]
            guard let (gamut, linear, format) = spaces[space] else { return nil }
            guard let v = Optional(parts.compactMap { amount($0, percentOf: 1) }), v.count == 3 else { return nil }
            let lin = linear ? (v[0], v[1], v[2]) : (gamut.decode(v[0]), gamut.decode(v[1]), gamut.decode(v[2]))
            return .success((RGBA(xyz: gamut.toXYZ(lin), a: alpha), format))
        case "lab", "lch":
            guard let l = amount(parts[0], percentOf: 100), let second = amount(parts[1], percentOf: function == "lab" ? 125 : 150) else { return nil }
            guard (0...100).contains(l) else { return .failure(Refusal(reason: "The lightness L* is from 0 to 100.")) }
            if function == "lab" {
                guard let b = amount(parts[2], percentOf: 125) else { return nil }
                return .success((RGBA(lab: (l, second, b), a: alpha), .lab))
            }
            guard let h = angle(parts[2]) else { return nil }
            return .success((RGBA(lab: (l, second * cos(h * .pi / 180), second * sin(h * .pi / 180)), a: alpha), .lch))
        case "oklab", "oklch":
            guard let l = amount(parts[0], percentOf: 1), let second = amount(parts[1], percentOf: 0.4) else { return nil }
            guard (0...1).contains(l) else { return .failure(Refusal(reason: "The lightness of OKLab is from 0 to 1, or 0% to 100%.")) }
            if function == "oklab" {
                guard let b = amount(parts[2], percentOf: 0.4) else { return nil }
                return .success((RGBA(oklab: (l, second, b), a: alpha), .oklab))
            }
            guard let h = angle(parts[2]) else { return nil }
            return .success((RGBA(oklab: (l, second * cos(h * .pi / 180), second * sin(h * .pi / 180)), a: alpha), .oklch))
        case "xyy":
            guard let x = Double(parts[0]), let y = Double(parts[1]), let Y = amount(parts[2], percentOf: 1) else { return nil }
            guard y > 0, x >= 0, x + y <= 1 else { return .failure(Refusal(reason: "x and y are from 0 to 1, y above nought, and x + y no more than 1.")) }
            guard Y >= 0 else { return .failure(Refusal(reason: "The luminance Y is not below nought.")) }
            return .success((RGBA(x: x, y: y, Y: Y, a: alpha), .xyy))
        default:
            guard let hue = angle(parts[0]), let second = amount(parts[1], percentOf: 1, bare: 0.01), let third = amount(parts[2], percentOf: 1, bare: 0.01) else { return nil }
            guard (0...1).contains(second), (0...1).contains(third) else {
                return .failure(Refusal(reason: "Saturation and \(function.hasPrefix("hsl") ? "lightness" : "brightness") are from 0% to 100%."))
            }
            let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let rgb = function.hasPrefix("hsl") ? fromHSL(h, second, third) : fromHSB(h, second, third)
            return .success((RGBA(r: rgb.0, g: rgb.1, b: rgb.2, a: alpha), function.hasPrefix("hsl") ? .hsl : .hsb))
        }
    }

    // 50%, 0.5, 128: a number, a percentage of the whole given, or bare, times what is given for that.
    private static func amount(_ s: String, percentOf whole: Double, bare: Double = 1) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("%") { return Double(t.dropLast()).map { $0 / 100 * whole } }
        return Double(t).map { $0 * bare }
    }

    private static func angle(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("deg") { return Double(t.dropLast(3)) }
        if t.hasSuffix("°") { return Double(t.dropLast()) }
        if t.hasSuffix("turn") { return Double(t.dropLast(4)).map { $0 * 360 } }
        if t.hasSuffix("rad") { return Double(t.dropLast(3)).map { $0 * 180 / .pi } }
        return Double(t)
    }

    // The colours of a gradient, evenly spaced from the first to the last.
    static func stops(_ a: RGBA, _ b: RGBA, _ n: Int) -> [RGBA] {
        (0..<n).map { i in mixed(a, b, 1 - Double(i) / Double(n - 1)) }
    }

    // Two colours mixed, the first's share given, channel by channel as Sass mixes them.
    static func mixed(_ a: RGBA, _ b: RGBA, _ w: Double) -> RGBA {
        RGBA(r: w * a.r + (1 - w) * b.r, g: w * a.g + (1 - w) * b.g, b: w * a.b + (1 - w) * b.b, a: w * a.a + (1 - w) * b.a)
    }

    // MARK: Converting

    static func fromHSL(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let c = (1 - abs(2 * l - 1)) * s
        return fromChroma(h, c, l - c / 2)
    }

    static func fromHSB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s
        return fromChroma(h, c, v - c)
    }

    private static func fromChroma(_ h: Double, _ c: Double, _ m: Double) -> (Double, Double, Double) {
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    struct Parts {
        var max: Double, min: Double, delta: Double
        var hue: Double, hslS: Double, l: Double, hsbS: Double, v: Double
        var c: Double, m: Double, y: Double, k: Double
    }

    // HSL, HSB and CMYK, of the colour as sRGB shows it.
    static func parts(_ colour: RGBA) -> Parts {
        let x = colour.clamped
        let hi = Swift.max(x.r, x.g, x.b), lo = Swift.min(x.r, x.g, x.b), d = hi - lo
        var hue = 0.0
        if d > 1e-12 {
            if hi == x.r { hue = 60 * ((x.g - x.b) / d).truncatingRemainder(dividingBy: 6) }
            else if hi == x.g { hue = 60 * ((x.b - x.r) / d + 2) }
            else { hue = 60 * ((x.r - x.g) / d + 4) }
            if hue < 0 { hue += 360 }
        }
        let l = (hi + lo) / 2
        let hslS = d < 1e-12 ? 0 : d / (1 - abs(2 * l - 1))
        let k = 1 - hi
        func ink(_ ch: Double) -> Double { k >= 1 - 1e-12 ? 0 : (1 - ch - k) / (1 - k) }
        return Parts(max: hi, min: lo, delta: d, hue: hue, hslS: hslS, l: l, hsbS: hi < 1e-12 ? 0 : d / hi, v: hi,
                     c: ink(x.r), m: ink(x.g), y: ink(x.b), k: k)
    }

    // MARK: Writing

    // 0.341 for 0.34117…, 60 for 60.000…: to the places given, and no trailing noughts.
    static func number(_ v: Double, _ places: Int = 1) -> String {
        var s = String(format: "%.\(places)f", v)
        if s.contains(".") { while s.hasSuffix("0") { s.removeLast() }; if s.hasSuffix(".") { s.removeLast() } }
        return s == "-0" ? "0" : s.replacingOccurrences(of: "-", with: "−")
    }

    private static func percent(_ v: Double) -> String { number(v * 100) + "%" }
    private static func alpha(_ x: RGBA) -> String { number(x.a, 2) }
    private static func plain(_ v: Double, _ places: Int) -> String { number(v, places).replacingOccurrences(of: "−", with: "-") }

    static func written(_ x: RGBA, _ format: Format) -> String {
        let (r, g, b) = x.bytes, p = parts(x), translucent = x.a < 1 - 1e-9
        let slash = translucent ? " / \(alpha(x))" : ""
        switch format {
        case .hex:
            return "#" + String(format: "%02X%02X%02X", r, g, b) + (translucent ? String(format: "%02X", Int((x.a * 255).rounded())) : "")
        case .rgb: return translucent ? "rgba(\(r), \(g), \(b), \(alpha(x)))" : "rgb(\(r), \(g), \(b))"
        case .hsl:
            let inner = "\(number(p.hue)), \(percent(p.hslS)), \(percent(p.l))"
            return translucent ? "hsla(\(inner), \(alpha(x)))" : "hsl(\(inner))"
        case .hsb: return "hsb(\(number(p.hue)), \(percent(p.hsbS)), \(percent(p.v)))"
        case .cmyk: return "cmyk(\(percent(p.c)), \(percent(p.m)), \(percent(p.y)), \(percent(p.k)))"
        case .name:
            let (name, _, exact) = nearest(x)
            return exact ? name : "near \(name)"
        case .p3, .rec2020:
            let gamut: Gamut = format == .p3 ? .p3 : .rec2020
            let (c1, c2, c3) = gamut.channels(x)
            return "color(\(format == .p3 ? "display-p3" : "rec2020") \(plain(c1, 4)) \(plain(c2, 4)) \(plain(c3, 4))\(slash))"
        case .lab:
            let (l, a, bb) = x.lab
            return "lab(\(plain(l, 2)) \(plain(a, 2)) \(plain(bb, 2))\(slash))"
        case .lch:
            let (l, a, bb) = x.lab, (c, h) = RGBA.polar(a, bb)
            return "lch(\(plain(l, 2)) \(plain(c, 2)) \(plain(h, 2))\(slash))"
        case .oklab:
            let (l, a, bb) = x.oklab
            return "oklab(\(plain(l, 4)) \(plain(a, 4)) \(plain(bb, 4))\(slash))"
        case .oklch:
            let (l, a, bb) = x.oklab, (c, h) = RGBA.polar(a, bb)
            return "oklch(\(plain(l * 100, 2))% \(plain(c, 4)) \(plain(c < 1e-6 ? 0 : h, 2))\(slash))"
        case .xyy:
            let (cx, cy, cY) = x.xyY
            return "xyY(\(String(format: "%.4f", cx)), \(String(format: "%.4f", cy)), \(String(format: "%.4f", cY)))"
        }
    }

    // The named colour of CSS nearest to it as the eye sees it, and whether it is that very colour.
    // Where CSS has two names for the one colour, fuchsia and magenta, both are given.
    static func nearest(_ x: RGBA) -> (String, RGBA, Bool) {
        var best = ("black", RGBA(r: 0, g: 0, b: 0), Double.infinity)
        for (name, hex) in named where !name.contains("grey") {
            guard case .success(let (c, _))? = read(hex) else { continue }
            let d = c.distance(to: RGBA(r: x.r, g: x.g, b: x.b))
            if d < best.2 || (d == best.2 && name < best.0) { best = (name, c, d) }
        }
        let same = named.filter { !$0.key.contains("grey") && $0.value == named[best.0] }.keys.sorted()
        return (same.count > 1 ? same.joined(separator: " or ") : best.0, best.1, x.inSRGB && best.1.bytes == x.bytes)
    }

    // Where it lies beyond sRGB, said: "outside sRGB, within Display P3".
    static func beyond(_ x: RGBA) -> String? {
        guard !x.inSRGB else { return nil }
        switch x.gamut {
        case .p3?: return "outside sRGB, within Display P3"
        case .rec2020?: return "outside Display P3, within Rec. 2020"
        default: return "outside Rec. 2020"
        }
    }

    // The colour shown, and the swatch.
    var result: RGBA? {
        switch kind {
        case .one(let x, _): return x
        case .mix(let a, let b, let w): return Colour.mixed(a, b, w)
        case .arithmetic(let tree, let inputs):
            var operations: [Operation] = []
            if case .colour(let x)? = try? Colour.evaluate(tree, inputs, &operations).0 { return x }
            return nil
        case .contrast, .distance, .gradient, .invalid: return nil
        }
    }

    private var operations: [Operation] {
        guard case .arithmetic(let tree, let inputs) = kind else { return [] }
        var operations: [Operation] = []
        _ = try? Colour.evaluate(tree, inputs, &operations)
        return operations
    }

    var swatch: Swatch? {
        switch kind {
        case .contrast(let fg, let bg): return .text(fg, on: bg)
        case .distance(let a, let b): return .pair(a, b)
        case .gradient(let a, let b, let n): return .gradient(Colour.stops(a, b, n))
        default: return result.map { .solid($0) }
        }
    }

    // The way it is written first: as asked, else not the way it was typed.
    private var shownFormat: Format {
        if let asked { return asked }
        if case .one(_, let typed) = kind { return typed == .hex ? .rgb : .hex }
        return .hex
    }

    // The other way it is written, beneath: for a colour beyond sRGB, a way that can hold it.
    private var secondFormat: Format {
        if let x = result, !x.inSRGB {
            if case .one(_, let typed) = kind, typed == .p3 || typed == .xyy { return typed == .p3 ? .xyy : .p3 }
            return shownFormat == .p3 ? .xyy : x.within(.p3) ? .p3 : .xyy
        }
        if case .one(_, .rgb) = kind, shownFormat == .hex { return .hsl }
        return shownFormat == .hex ? .rgb : .hex
    }

    var ratio: Double? {
        guard case .contrast(let a, let b) = kind else { return nil }
        let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    // What a ΔE means to the eye, as the usual rule of thumb has it.
    static func seen(_ d: Double) -> String {
        switch d {
        case ..<1: return "Not perceptible to the eye"
        case ..<2: return "Perceptible on close looking"
        case ..<10: return "Perceptible at a glance"
        case ..<50: return "Clearly different colours"
        default: return "Very different colours"
        }
    }

    private static func levels(_ ratio: Double) -> String {
        if ratio >= 7 { return "Meets AAA for all text" }
        if ratio >= 4.5 { return "Meets AA for all text, and AAA for large text" }
        if ratio >= 3 { return "Meets AA for large text only" }
        return "Fails every WCAG level for text"
    }

    var solution: Solution {
        switch kind {
        case .invalid(let why): return Solution(exact: "Not a colour", approx: why)
        case .contrast:
            let r = ratio!
            return Solution(exact: "\(Colour.number(r, 2)) : 1", approx: "Contrast ratio. " + Colour.levels(r) + ".")
        case .distance(let a, let b):
            let d = a.distance(to: b)
            return Solution(exact: "ΔE = \(Colour.number(d, 2))", approx: Colour.seen(d))
        case .gradient(let a, let b, let n):
            let all = Colour.stops(a, b, n).map { Colour.written($0, .hex) }
            let shown = n <= 6 ? all.joined(separator: ", ") : (all.prefix(3) + ["…"] + all.suffix(2)).joined(separator: ", ")
            return Solution(exact: shown, approx: "\(n) colours, evenly from \(all.first!) to \(all.last!)")
        case .one, .mix, .arithmetic:
            guard let x = result else { return Solution(exact: "Not a colour", approx: nil) }
            var second = Colour.written(x, secondFormat)
            if let beyond = Colour.beyond(x) {
                second += "; " + beyond + (shownFormat == .hex || shownFormat == .rgb ? ", so the hex is the nearest sRGB can show" : "")
            } else if shownFormat != .name {
                let (name, _, exact) = Colour.nearest(x)
                second += exact ? ", which is \(name)" : ", near \(name)"
            }
            if case .mix(_, _, let w) = kind { second = "\(Colour.number(w * 100))% and \(Colour.number(100 - w * 100))% mixed: " + second }
            return Solution(exact: Colour.written(x, shownFormat), approx: second)
        }
    }

    var copyText: String? {
        switch kind {
        case .invalid: return nil
        case .contrast: return Colour.number(ratio!, 2)
        case .distance(let a, let b): return Colour.number(a.distance(to: b), 2)
        case .gradient(let a, let b, let n): return Colour.stops(a, b, n).map { Colour.written($0, .hex) }.joined(separator: ", ")
        case .one, .mix, .arithmetic: return result.map { Colour.written($0, shownFormat) }
        }
    }

    // MARK: The chromaticity diagram

    // The colours on the diagram, made again from the inputs whenever one is dragged or the share moved.
    var chromaticity: Chromaticity? {
        func mark(_ x: RGBA, _ label: String, result: Bool = false, input: Int? = nil) -> Chromaticity.Mark {
            .init(colour: x, label: label, result: result, input: input)
        }
        func path(_ a: RGBA, _ b: RGBA) -> [RGBA] { (0...40).map { Colour.mixed(a, b, 1 - Double($0) / 40) } }
        switch kind {
        case .invalid: return nil
        case .one(let x, _):
            return Chromaticity(inputs: [x], share: nil) { inputs, _ in .init(marks: [mark(inputs[0], Colour.written(inputs[0], .hex), result: true, input: 0)]) }
        case .mix(let a, let b, let w):
            return Chromaticity(inputs: [a, b], share: w) { inputs, share in
                let made = Colour.mixed(inputs[0], inputs[1], share)
                return .init(marks: [mark(inputs[0], "A", input: 0), mark(inputs[1], "B", input: 1), mark(made, "Result", result: true)],
                             path: path(inputs[0], inputs[1]), onPath: 2)
            }
        case .gradient(let a, let b, let n):
            return Chromaticity(inputs: [a, b], share: 0.5) { inputs, share in
                var marks = Colour.stops(inputs[0], inputs[1], n).dropFirst().dropLast().map { Chromaticity.Mark(colour: $0, label: "", small: true) }
                marks.insert(mark(inputs[0], "A", input: 0), at: 0)
                marks.append(mark(inputs[1], "B", input: 1))
                marks.append(mark(Colour.mixed(inputs[0], inputs[1], share), "Result", result: true))
                return .init(marks: marks, path: path(inputs[0], inputs[1]), onPath: marks.count - 1)
            }
        case .distance(let a, let b), .contrast(let a, let b):
            return Chromaticity(inputs: [a, b], share: nil) { inputs, _ in
                .init(marks: [mark(inputs[0], "A", input: 0), mark(inputs[1], "B", input: 1)], lines: [(0, 1)])
            }
        case .arithmetic(let tree, let typedInputs):
            return Chromaticity(inputs: typedInputs, share: nil) { inputs, _ in
                var operations: [Operation] = []
                _ = try? Colour.evaluate(tree, inputs, &operations)
                var marks = inputs.enumerated().map { mark($1, Colour.letter($0), input: $0) }
                var lines: [(Int, Int)] = []
                for (i, operation) in operations.enumerated() {
                    let last = i == operations.count - 1
                    marks.append(mark(operation.result, last ? "Result" : operation.text, result: last))
                    for from in [operation.leftMark, operation.rightMark].compactMap({ $0 }) { lines.append((from, marks.count - 1)) }
                }
                return .init(marks: marks, lines: lines)
            }
        }
    }

    // MARK: Working

    var details: Details? {
        var steps: [Step] = []
        let heading: String
        func finished(_ solutions: [Math]) -> Details {
            var d = Details(name: "", equation: t(heading), steps: steps, solutions: solutions, note: nil, f: { _ in .nan }, roots: [])
            d.chromaticity = chromaticity
            return d
        }
        switch kind {
        case .invalid: return nil
        case .one(let x, let typed):
            heading = typed == .name ? Colour.nearest(x).0 : typed == .hex ? Colour.written(x, .hex) : typedColour
            steps += Colour.reading(x, typed)
            steps += Colour.conversions(x, skipping: typed)
        case .mix(let a, let b, let w):
            heading = typed
            steps.append(Step(label: "Reading the colours", math: t("A = \(Colour.written(a, .rgb)),  B = \(Colour.written(b, .rgb))")))
            let x = result!
            func channel(_ name: String, _ p: Double, _ q: Double, _ out: Double) -> String {
                "\(name) = \(Colour.number(w, 2)) × \(Colour.number(p * 255, 1)) + \(Colour.number(1 - w, 2)) × \(Colour.number(q * 255, 1)) = \(Colour.number(out * 255, 1))"
            }
            steps.append(Step(label: "Mixing the red", math: t(channel("R", a.r, b.r, x.r)),
                              note: "Each channel of the mixture is \(Colour.number(w * 100))% of A's and \(Colour.number(100 - w * 100))% of B's."))
            steps.append(Step(label: "Mixing the green", math: t(channel("G", a.g, b.g, x.g))))
            steps.append(Step(label: "Mixing the blue", math: t(channel("B", a.b, b.b, x.b))))
            steps.append(Step(label: "Rounding to whole channels", math: t(Colour.written(x, .rgb) + " = " + Colour.written(x, .hex))))
            steps += Colour.conversions(x, skipping: .hex)
        case .arithmetic(_, let inputs):
            heading = typed
            steps.append(Step(label: inputs.count == 1 ? "Reading the colour" : "Reading the colours",
                              math: t(inputs.enumerated().map { "\(Colour.letter($0)) = \(Colour.written($1, .rgb))" }.joined(separator: ",  "))))
            for operation in operations { steps.append(Colour.step(operation)) }
            let x = result!
            steps.append(Step(label: "Writing it in hexadecimal", math: t(Colour.written(x, .rgb) + " = " + Colour.written(x, .hex))))
            steps += Colour.conversions(x, skipping: .hex)
        case .distance(let a, let b):
            heading = typed
            let (l1, a1, b1) = a.lab, (l2, a2, b2) = b.lab
            steps.append(Step(label: "Reading the colours", math: t("A = \(Colour.written(a, .hex)),  B = \(Colour.written(b, .hex))")))
            steps.append(Step(label: "Converting A to CIELAB", math: t("(L*, a*, b*) = (\(Colour.number(l1, 2)), \(Colour.number(a1, 2)), \(Colour.number(b1, 2)))"),
                              note: "By way of linear RGB and XYZ, adapted to D50 as CSS has it; L* is the lightness, a* runs from green to red and b* from blue to yellow."))
            steps.append(Step(label: "Converting B to CIELAB", math: t("(L*, a*, b*) = (\(Colour.number(l2, 2)), \(Colour.number(a2, 2)), \(Colour.number(b2, 2)))")))
            let gap = a.distance(to: b)
            steps.append(Step(label: "Finding the distance between them",
                              math: t("ΔE = √(ΔL*² + Δa*² + Δb*²) = √(\(Colour.number(l1 - l2, 2))² + \(Colour.number(a1 - a2, 2))² + \(Colour.number(b1 - b2, 2))²) = \(Colour.number(gap, 2))"),
                              note: "The CIE 1976 difference. " + Colour.seen(gap) + ": below 1 the eye sees no difference, and about 2.3 is the least it notices."))
            return finished([t(solution.exact)])
        case .gradient(let a, let b, let n):
            heading = typed
            steps.append(Step(label: "Reading the colours", math: t("A = \(Colour.written(a, .rgb)),  B = \(Colour.written(b, .rgb))")))
            steps.append(Step(label: "Spacing the steps evenly", math: t("cₖ = A + (B − A) × k/\(n - 1),  k = 0, 1, …, \(n - 1)"),
                              note: "Each channel goes in \(n - 1) equal steps from A's to B's, and is rounded to a whole number."))
            return finished(Colour.stops(a, b, n).map { t(Colour.written($0, .hex) + "   " + Colour.written($0, .rgb)) })
        case .contrast(let a, let b):
            heading = typed
            steps.append(Step(label: "Reading the colours", math: t("\(Colour.written(a, .hex)) = \(Colour.written(a, .rgb)),  \(Colour.written(b, .hex)) = \(Colour.written(b, .rgb))")))
            steps.append(Step(label: "Finding the relative luminance of each", math: t("L = 0.2126 R + 0.7152 G + 0.0722 B"),
                              note: "Each channel, from 0 to 1, is first made linear: c/12.92 up to 0.04045, ((c + 0.055)/1.055)^2.4 above."))
            steps.append(Step(label: "Working out each", math: t("L₁ = \(Colour.number(a.luminance, 4)),  L₂ = \(Colour.number(b.luminance, 4))")))
            let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
            steps.append(Step(label: "Dividing the lighter by the darker", math: t("(\(Colour.number(hi, 4)) + 0.05)/(\(Colour.number(lo, 4)) + 0.05) = \(Colour.number(ratio!, 2))")))
            steps.append(Step(label: "Comparing with WCAG 2", math: nil,
                              note: "AA asks 4.5 : 1 for text and 3 : 1 for large text; AAA asks 7 : 1 and 4.5 : 1. " + Colour.levels(ratio!) + "."))
            return finished([t(solution.exact)])
        }
        let x = result!
        var solutions = Colour.listed.map { t(Colour.written(x, $0)) }
        let (name, _, exact) = Colour.nearest(x)
        if exact { solutions.append(t(name)) }
        // The way shown on the card first.
        if let first = solutions.firstIndex(where: { $0.plain == Colour.written(x, shownFormat) }) { solutions.insert(solutions.remove(at: first), at: 0) }
        else { solutions.insert(t(Colour.written(x, shownFormat)), at: 0) }
        return finished(solutions)
    }

    // One operation on light, channel by channel, in 0 to 255.
    private static func step(_ operation: Operation) -> Step {
        let x = operation.result
        func v(_ c: Double) -> String { number(c * 255, 1) }
        func line(_ name: String, _ pick: (RGBA) -> Double) -> String {
            let out = v(pick(x))
            switch (operation.op, operation.left, operation.right) {
            case ("×", .colour(let a), .colour(let b)):
                return "\(name) = \(v(pick(a.clamped))) × \(v(pick(b.clamped)))/255 = \(out)"
            case (_, .colour(let a), .colour(let b)):
                let raw = pick(a.clamped) * 255 + (operation.op == "+" ? 1 : -1) * pick(b.clamped) * 255
                return "\(name) = \(v(pick(a.clamped))) \(operation.op) \(v(pick(b.clamped))) = \(number(raw, 1))" + (abs(raw - pick(x) * 255) > 1e-6 ? " → \(out)" : "")
            case (_, .colour(let a), .number(let k)), (_, .number(let k), .colour(let a)):
                let raw = operation.op == "×" ? pick(a.clamped) * 255 * k : pick(a.clamped) * 255 / k
                return "\(name) = \(v(pick(a.clamped))) \(operation.op) \(number(k, 4)) = \(number(raw, 1))" + (abs(raw - pick(x) * 255) > 1e-6 ? " → \(out)" : "")
            default: return ""
            }
        }
        let math = t([line("R") { $0.r }, line("G") { $0.g }, line("B") { $0.b }].joined(separator: ",  "))
        switch (operation.op, operation.left, operation.right) {
        case ("+", _, _):
            return Step(label: "Adding the light of each channel: \(operation.text)", math: math, note: "Light adds: each channel is the sum, and no more than 255.")
        case ("−", _, _):
            return Step(label: "Taking away the light of each channel: \(operation.text)", math: math, note: "Each channel is the difference, and no less than 0.")
        case ("×", .colour, .colour):
            return Step(label: "Multiplying the channels: \(operation.text)", math: math,
                        note: "Each channel is the product of the two as fractions of 255: light through one filter and then the other.")
        case ("×", _, _):
            return Step(label: "Scaling the light: \(operation.text)", math: math, note: "Each channel is multiplied, and no more than 255.")
        default:
            return Step(label: "Dividing the light: \(operation.text)", math: math, note: "Each channel is divided: the same colour, dimmer.")
        }
    }

    // What was typed of the colour itself, without "colour" or "to hsl".
    private var typedColour: String {
        var s = typed
        if let m = s.lowercased().range(of: "\\s+(to|in|as)\\s+[\\w-]+$", options: .regularExpression) { s = String(s[..<m.lowerBound]) }
        if let m = s.lowercased().range(of: "^colou?r(\\s+of)?\\s+", options: .regularExpression) { s = String(s[m.upperBound...]) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    // How the colour typed comes to its red, green and blue.
    private static func reading(_ x: RGBA, _ typed: Format) -> [Step] {
        let (r, g, b) = x.bytes
        let hex = String(format: "%02X %02X %02X", r, g, b).split(separator: " ").map(String.init)
        switch typed {
        case .hex:
            return [Step(label: "Reading each pair of hexadecimal digits", math: t("\(hex[0]) = \(r),  \(hex[1]) = \(g),  \(hex[2]) = \(b)"),
                         note: "Each pair is one channel, red, green and blue, from 00 to FF, which is 0 to 255.")]
        case .rgb:
            return [Step(label: "Writing each channel in hexadecimal", math: t("\(r) = \(hex[0]),  \(g) = \(hex[1]),  \(b) = \(hex[2])"))]
        case .name:
            return [Step(label: "Reading the named colour", math: t("\(Colour.nearest(x).0) = \(Colour.written(x, .hex)) = \(Colour.written(x, .rgb))"),
                         note: "It is one of the colours CSS names.")]
        case .hsl, .hsb:
            let p = parts(x), hsl = typed == .hsl
            let s = hsl ? p.hslS : p.hsbS, third = hsl ? p.l : p.v
            var steps = [Step(label: "Finding the chroma",
                              math: t(hsl ? "C = (1 − |2L − 1|) × S = (1 − |2 × \(number(third, 3)) − 1|) × \(number(s, 3)) = \(number(p.delta, 3))"
                                          : "C = B × S = \(number(third, 3)) × \(number(s, 3)) = \(number(p.delta, 3))"))]
            let xPart = p.delta * (1 - abs((p.hue / 60).truncatingRemainder(dividingBy: 2) - 1))
            steps.append(Step(label: "Finding the second component", math: t("X = C × (1 − |(H/60°) mod 2 − 1|) = \(number(xPart, 3))")))
            steps.append(Step(label: "Finding what is added to each channel",
                              math: t(hsl ? "m = L − C/2 = \(number(p.min, 3))" : "m = B − C = \(number(p.min, 3))"),
                              note: "The hue, \(number(p.hue))°, lies between \(Int(p.hue / 60) * 60)° and \(Int(p.hue / 60) * 60 + 60)°, which says which channel takes C, which X and which nought."))
            steps.append(Step(label: "Scaling to 0–255", math: t("(R, G, B) = (\(number(x.r * 255)), \(number(x.g * 255)), \(number(x.b * 255))) → \(written(x, .rgb))")))
            return steps
        case .cmyk:
            let p = parts(x)
            return [Step(label: "Taking out the black", math: t("R = 255 × (1 − C)(1 − K) = \(number(x.r * 255))"),
                         note: "And in the same way G = 255 × (1 − M)(1 − K) = \(number(x.g * 255)), B = 255 × (1 − Y)(1 − K) = \(number(x.b * 255)); here K = \(percent(p.k))."),
                    Step(label: "Rounding to whole channels", math: t(written(x, .rgb)))]
        case .p3, .rec2020, .lab, .lch, .oklab, .oklch, .xyy:
            let (X, Y, Z) = x.xyz
            let from: String
            switch typed {
            case .p3: from = "Display P3's channels are taken off its curve and multiplied by its matrix."
            case .rec2020: from = "Rec. 2020's channels are taken off its curve and multiplied by its matrix."
            case .lab, .lch: from = "CIELAB under D50, as CSS has it, is turned into XYZ and adapted to D65 by Bradford's method."
            case .oklab, .oklch: from = "OKLab is turned into the cone responses, cubed, and those into linear sRGB."
            default: from = "X = xY/y and Z = (1 − x − y)Y/y."
            }
            var steps = [Step(label: "Converting to CIE XYZ", math: t("X = \(number(X, 4)),  Y = \(number(Y, 4)),  Z = \(number(Z, 4))"), note: from)]
            let (lr, lg, lb) = Gamut.srgb.fromXYZ(x.xyz)
            steps.append(Step(label: "Converting to linear sRGB", math: t("R = \(number(lr, 4)),  G = \(number(lg, 4)),  B = \(number(lb, 4))")))
            steps.append(Step(label: "Applying the sRGB curve", math: t("R′ = \(number(x.r, 4)),  G′ = \(number(x.g, 4)),  B′ = \(number(x.b, 4))"),
                              note: beyond(x).map { "A channel below 0 or above 1: the colour is \($0). It is marked on the diagram where it truly lies; hex and rgb give the nearest sRGB can show, each channel clipped." }))
            steps.append(Step(label: "Rounding to whole channels", math: t(written(x, .rgb))))
            return steps
        }
    }

    // Into each of the other ways of writing it, from the channels as fractions of 255.
    private static func conversions(_ colour: RGBA, skipping typed: Format) -> [Step] {
        let p = parts(colour), x = colour.clamped
        var steps = [Step(label: "Scaling the channels to 0–1",
                          math: t("R′ = \(number(x.r * 255))/255 = \(number(x.r, 3)),  G′ = \(number(x.g * 255))/255 = \(number(x.g, 3)),  B′ = \(number(x.b * 255))/255 = \(number(x.b, 3))")),
                     Step(label: "Finding the largest and the smallest",
                          math: t("max = \(number(p.max, 3)),  min = \(number(p.min, 3)),  Δ = max − min = \(number(p.delta, 3))"))]
        if p.delta < 1e-12 {
            steps.append(Step(label: "Finding the hue", math: t("H = 0°"), note: "The three channels are equal: it is a grey, which has no hue."))
        } else {
            let formula: String
            if p.max == x.r { formula = "H = 60° × ((G′ − B′)/Δ mod 6)" }
            else if p.max == x.g { formula = "H = 60° × ((B′ − R′)/Δ + 2)" }
            else { formula = "H = 60° × ((R′ − G′)/Δ + 4)" }
            steps.append(Step(label: "Finding the hue", math: t("\(formula) = \(number(p.hue))°")))
        }
        if typed != .hsl {
            steps.append(Step(label: "Finding the lightness", math: t("L = (max + min)/2 = \(percent(p.l))")))
            steps.append(Step(label: "Finding the saturation of HSL",
                              math: t(p.delta < 1e-12 ? "S = 0%" : "S = Δ/(1 − |2L − 1|) = \(percent(p.hslS))")))
        }
        if typed != .hsb {
            steps.append(Step(label: "Finding the brightness", math: t("B = max = \(percent(p.v))")))
            steps.append(Step(label: "Finding the saturation of HSB", math: t(p.max < 1e-12 ? "S = 0%" : "S = Δ/max = \(percent(p.hsbS))")))
        }
        if typed != .cmyk {
            steps.append(Step(label: "Finding the black of CMYK", math: t("K = 1 − max = \(percent(p.k))")))
            steps.append(Step(label: "Finding the cyan, magenta and yellow",
                              math: t(p.k >= 1 - 1e-12 ? "C = M = Y = 0%" : "C = (1 − R′ − K)/(1 − K) = \(percent(p.c)),  M = \(percent(p.m)),  Y = \(percent(p.y))")))
        }
        // Where it lies on the diagram: from the colour itself, beyond sRGB or not.
        let (X, Y, Z) = colour.xyz, (cx, cy, _) = colour.xyY
        steps.append(Step(label: "Finding the CIE xyY",
                          math: t("x = X/(X + Y + Z) = \(String(format: "%.4f", cx)),  y = Y/(X + Y + Z) = \(String(format: "%.4f", cy)),  Y = \(String(format: "%.4f", Y))"),
                          note: "From X = \(number(X, 4)), Y = \(number(Y, 4)), Z = \(number(Z, 4)): its place on the chromaticity diagram below, and its luminance."))
        let (name, near, exact) = nearest(colour)
        steps.append(Step(label: "Finding the nearest named colour",
                          math: t(exact ? "\(name) = \(written(near, .hex))" : "\(name) = \(written(near, .hex)),  ΔE = \(number(colour.distance(to: near)))"),
                          note: exact ? "It is the colour CSS calls \(name)." : "The nearest of the colours CSS names, as the eye sees the difference (ΔE in CIELAB)."))
        let (white, black) = ((1.05) / (colour.luminance + 0.05), (colour.luminance + 0.05) / 0.05)
        steps.append(Step(label: "Finding the contrast with white and with black",
                          math: t("\(number(white, 2)) : 1 with white,  \(number(black, 2)) : 1 with black"),
                          note: "Text in \(white >= black ? "white" : "black") reads better on it."))
        return steps
    }

    // MARK: Named colours

    // The 148 colours CSS names, grey and gray both.
    static let named: [String: String] = {
        let list = """
        aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4 black 000000
        blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00
        chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff darkblue 00008b
        darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b darkmagenta 8b008b
        darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 darksalmon e9967a darkseagreen 8fbc8f
        darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493
        deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222 floralwhite fffaf0 forestgreen 228b22
        fuchsia ff00ff gainsboro dcdcdc ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 green 008000 greenyellow adff2f
        grey 808080 honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa
        lavenderblush fff0f5 lawngreen 7cfc00 lemonchiffon fffacd lightblue add8e6 lightcoral f08080 lightcyan e0ffff
        lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 lightpink ffb6c1 lightsalmon ffa07a
        lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 lightsteelblue b0c4de lightyellow ffffe0
        lime 00ff00 limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 mediumaquamarine 66cdaa mediumblue 0000cd
        mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 mediumslateblue 7b68ee mediumspringgreen 00fa9a
        mediumturquoise 48d1cc mediumvioletred c71585 midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5
        navajowhite ffdead navy 000080 oldlace fdf5e6 olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6
        palegoldenrod eee8aa palegreen 98fb98 paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9
        peru cd853f pink ffc0cb plum dda0dd powderblue b0e0e6 purple 800080 rebeccapurple 663399 red ff0000 rosybrown bc8f8f
        royalblue 4169e1 saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee sienna a0522d
        silver c0c0c0 skyblue 87ceeb slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa springgreen 00ff7f
        steelblue 4682b4 tan d2b48c teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 violet ee82ee wheat f5deb3
        white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32
        """
        let words = list.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        var table: [String: String] = [:]
        for i in stride(from: 0, to: words.count - 1, by: 2) { table[words[i]] = "#" + words[i + 1] }
        return table
    }()
}
