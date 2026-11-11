import Foundation

// 5 km to miles, 100 F in C, 255 in hex, hex(255): a quantity said in another unit, or a whole
// number in another base. The left of "to" or "in" is worked out as any sum is; what is on the
// right is only a name.
struct Conversion {
    var value: Double          // the answer, as a number: what is copied and what ans becomes
    var text: String           // the answer as it is shown: 3.10686 mi, FF
    var approx: String?        // beneath it
    var details: Details

    var solution: Solution { Solution(exact: text, approx: approx) }

    // What is copied: a number for a quantity, the digits with their prefix for a base.
    var copy: String?
    var copyText: String { copy ?? (text.hasPrefix("=") ? String(format: "%.12g", value) : text.replacingOccurrences(of: "−", with: "-")) }

    static func parse(_ input: String) -> Conversion? {
        let text = input.trimmingCharacters(in: .whitespaces)
        if let base = Bases.parse(text) { return base }
        if let money = Currency.parse(text) { return money }
        if let form = NumberForms.parse(text) { return form }
        if let height = Units.parseFeet(text) { return height }
        if let units = Units.parse(text) { return units }
        return Units.parseSum(text, target: nil)
    }
}

// MARK: - Bases

enum Bases {
    private static let names: [String: Int] = [
        "hex": 16, "hexadecimal": 16, "bin": 2, "binary": 2, "oct": 8, "octal": 8, "dec": 10, "decimal": 10, "unary": 1, "tally": 1,
    ]

    static func parse(_ text: String) -> Conversion? {
        var quantity: String, base: Int
        if let match = text.range(of: "^(hex|bin|oct|dec)\\((.+)\\)$", options: [.regularExpression, .caseInsensitive]) {
            let whole = String(text[match])
            let name = String(whole[..<whole.firstIndex(of: "(")!]).lowercased()
            quantity = String(whole[whole.index(after: whole.firstIndex(of: "(")!)..<whole.index(before: whole.endIndex)])
            base = names[name]!
        } else if let match = text.range(of: "\\s+(?:to|in|into|as)\\s+(?:base\\s*([0-9]{1,2})|(hexadecimal|hex|binary|bin|octal|oct|decimal|dec|unary|tally))\\s*$", options: [.regularExpression, .caseInsensitive]) {
            let tail = text[match].trimmingCharacters(in: .whitespaces).lowercased()
            let word = tail.split(separator: " ").dropFirst().joined(separator: "").replacingOccurrences(of: "base", with: "")
            guard let chosen = names[word] ?? Int(word), (1...36).contains(chosen) else { return nil }
            base = chosen
            quantity = String(text[..<match.lowerBound])
        } else {
            return nil
        }
        guard let expr = try? Parser.constant(quantity), !expr.hasUnknown else { return nil }
        let v = expr.eval(0)
        guard v.isFinite, v == v.rounded(), abs(v) < 9e15 else { return nil }
        let n = Int(v)
        // Base 1 has one digit, and a number is that many of it: 255 is 255 ones.
        if base == 1 { guard abs(n) <= 10_000 else { return nil } }
        let digits = base == 1 ? (n == 0 ? "0" : String(repeating: "1", count: abs(n))) : String(abs(n), radix: base).uppercased()
        let prefix = Options.basePrefix ? [16: "0x", 2: "0b", 8: "0o"][base] ?? "" : ""
        let sign = n < 0 ? "−" : ""
        let shown = "\(sign)\(prefix)\(digits)"
        let spelled = base == 10 ? "" : "base \(base)"

        var d = Details(name: "", equation: t(text), steps: [], solutions: [t(shown)], note: nil, f: { _ in .nan }, roots: [])
        if base == 1 {
            d.steps.append(Step(label: "Writing one 1 for each unit", math: nil,
                                note: "In base 1 there is a single digit, and a number is as many of it as it is large: \(abs(n)) is \(abs(n)) ones."))
        } else if base != 10, let sum = operands(of: quantity) {
            // 16 − 15 in binary: each number written in the base, and then the sum done in it.
            func written(_ m: Int) -> String { (m < 0 ? "−" : "") + prefix + String(abs(m), radix: base).uppercased() }
            for m in sum.a == sum.b ? [sum.a] : [sum.a, sum.b] {
                d.steps.append(Step(label: "Writing \(m) in base \(base)", math: t("\(m) = \(written(m)) (base \(base))")))
            }
            d.steps.append(Step(label: "Working it out in base \(base)", math: t("\(written(sum.a)) \(sum.symbol) \(written(sum.b)) = \(shown) (base \(base))")))
        } else if base != 10 {
            // Divided by the base until nothing is left; the remainders, read upwards, are the digits.
            var rest = abs(n)
            var lines: [String] = []
            repeat {
                lines.append("\(rest) = \(rest / base)·\(base) + \(rest % base)")
                rest /= base
            } while rest > 0 && lines.count < 64
            let shownLines = lines.count > 10 ? Array(lines.prefix(4)) + ["…"] + Array(lines.suffix(3)) : lines
            for (i, line) in shownLines.enumerated() {
                d.steps.append(Step(label: i == 0 ? "Dividing by \(base)" : "Dividing the quotient by \(base)", math: t(line)))
            }
            d.steps.append(Step(label: "Reading the remainders", math: nil, note: "The remainders, from the last to the first, are the digits: \(digits)."))
        }
        d.steps.append(Step(label: "Hence", math: t("\(sign)\(abs(n)) = \(shown)\(spelled.isEmpty ? "" : " (\(spelled))")")))
        // The other bases beneath it, as a programmer would look for them.
        var others: [String] = []
        for (label, b) in [("decimal", 10), ("hexadecimal", 16), ("binary", 2), ("octal", 8)] where b != base {
            let p = Options.basePrefix ? [16: "0x", 2: "0b", 8: "0o", 10: ""][b]! : ""
            others.append("\(label) \(sign)\(p)\(groups(String(abs(n), radix: b).uppercased(), b))")
        }
        let approx = others.prefix(3).joined(separator: " · ")
        d.solutions.append(t(others.joined(separator: "; ")))
        return Conversion(value: Double(n), text: shown, approx: approx, details: d)
    }

    // Two whole numbers with a sign between them: 16-15, 255 + 1, 12 * 12.
    private static func operands(of quantity: String) -> (a: Int, b: Int, symbol: String)? {
        let pattern = "^\\s*([0-9]{1,15})\\s*([-+−*×·/÷])\\s*([0-9]{1,15})\\s*$"
        guard let r = try? NSRegularExpression(pattern: pattern),
              let m = r.firstMatch(in: quantity, range: NSRange(quantity.startIndex..., in: quantity)),
              let a = Range(m.range(at: 1), in: quantity).flatMap({ Int(quantity[$0]) }),
              let sign = Range(m.range(at: 2), in: quantity).map({ String(quantity[$0]) }),
              let b = Range(m.range(at: 3), in: quantity).flatMap({ Int(quantity[$0]) }) else { return nil }
        let symbol = ["-": "−", "*": "×", "·": "×", "/": "÷"][sign] ?? sign
        return (a, b, symbol)
    }

    // Four to a group in binary and hexadecimal, from the right: 1111 1111.
    private static func groups(_ s: String, _ base: Int) -> String {
        guard base == 2 || base == 16, s.count > 4 else { return s }
        var out = "", count = 0
        for c in s.reversed() {
            if count > 0, count % 4 == 0 { out.append(" ") }
            out.append(c)
            count += 1
        }
        return String(out.reversed())
    }
}

// MARK: - Units

enum Units {
    enum Kind { case length, mass, volume, time, speed, area, data, energy, power, pressure, force, angle, frequency, temperature }

    struct Unit { var kind: Kind; var factor: Double; var name: String }

    // factor: how many of the base unit one of these is. Temperature is dealt with apart.
    private static let table: [String: Unit] = {
        var t: [String: Unit] = [:]
        func add(_ names: [String], _ kind: Kind, _ factor: Double, shown: String? = nil) {
            for n in names { t[n] = Unit(kind: kind, factor: factor, name: shown ?? names[0]) }
        }
        // length, in metres
        add(["m", "meter", "meters", "metre", "metres"], .length, 1)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], .length, 1000)
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres"], .length, 0.01)
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres"], .length, 0.001)
        add(["um", "µm", "micron", "microns", "micrometer", "micrometre"], .length, 1e-6)
        add(["nm", "nanometer", "nanometers", "nanometre", "nanometres"], .length, 1e-9)
        add(["mi", "mile", "miles"], .length, 1609.344)
        add(["yd", "yard", "yards"], .length, 0.9144)
        add(["ft", "foot", "feet"], .length, 0.3048)
        add(["in", "inch", "inches"], .length, 0.0254)
        add(["nmi", "nauticalmile", "nauticalmiles"], .length, 1852)
        add(["ly", "lightyear", "lightyears"], .length, 9.4607304725808e15)
        add(["au", "astronomicalunit"], .length, 1.495978707e11)
        add(["angstrom", "å"], .length, 1e-10)
        // mass, in kilograms
        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], .mass, 1)
        add(["g", "gram", "grams"], .mass, 0.001)
        add(["mg", "milligram", "milligrams"], .mass, 1e-6)
        add(["ug", "µg", "microgram", "micrograms"], .mass, 1e-9)
        add(["t", "tonne", "tonnes"], .mass, 1000)
        add(["lb", "lbs", "pound", "pounds"], .mass, 0.45359237)
        add(["oz", "ounce", "ounces"], .mass, 0.028349523125)
        add(["st", "stone"], .mass, 6.35029318)
        // volume, in litres
        add(["l", "L", "liter", "liters", "litre", "litres"], .volume, 1)
        add(["ml", "mL", "milliliter", "milliliters", "millilitre", "millilitres", "cc"], .volume, 0.001)
        add(["cl", "centiliter", "centilitre"], .volume, 0.01)
        add(["dl", "deciliter", "decilitre"], .volume, 0.1)
        add(["m3", "cubicmeter", "cubicmetre"], .volume, 1000)
        add(["cm3", "cubiccentimeter", "cubiccentimetre"], .volume, 0.001)
        add(["gal", "gallon", "gallons"], .volume, 3.785411784)
        add(["qt", "quart", "quarts"], .volume, 0.946352946)
        add(["pt", "pint", "pints"], .volume, 0.473176473)
        add(["cup", "cups"], .volume, 0.2365882365)
        add(["floz", "fluidounce", "fluidounces"], .volume, 0.0295735295625)
        add(["tbsp", "tablespoon", "tablespoons"], .volume, 0.01478676478125)
        add(["tsp", "teaspoon", "teaspoons"], .volume, 0.00492892159375)
        add(["igal", "imperialgallon"], .volume, 4.54609)
        // time, in seconds
        add(["s", "sec", "second", "seconds"], .time, 1)
        add(["ms", "millisecond", "milliseconds"], .time, 0.001)
        add(["us", "µs", "microsecond", "microseconds"], .time, 1e-6)
        add(["ns", "nanosecond", "nanoseconds"], .time, 1e-9)
        add(["min", "mins", "minute", "minutes"], .time, 60)
        add(["h", "hr", "hrs", "hour", "hours"], .time, 3600)
        add(["d", "day", "days"], .time, 86400)
        add(["wk", "week", "weeks"], .time, 604800)
        add(["yr", "year", "years"], .time, 31557600)
        // speed, in metres per second
        add(["m/s", "mps"], .speed, 1)
        add(["km/h", "kmh", "kph", "kmph"], .speed, 1 / 3.6)
        add(["mph", "mi/h"], .speed, 0.44704)
        add(["kn", "kt", "knot", "knots"], .speed, 1852.0 / 3600)
        add(["ft/s", "fps"], .speed, 0.3048)
        // area, in square metres
        add(["m2", "sqm", "squaremeter", "squaremeters", "squaremetre", "squaremetres"], .area, 1)
        add(["km2", "sqkm", "squarekilometer", "squarekilometre"], .area, 1e6)
        add(["cm2", "sqcm", "squarecentimeter", "squarecentimetre"], .area, 1e-4)
        add(["ha", "hectare", "hectares"], .area, 1e4)
        add(["acre", "acres"], .area, 4046.8564224)
        add(["ft2", "sqft", "squarefoot", "squarefeet"], .area, 0.09290304)
        add(["in2", "sqin", "squareinch", "squareinches"], .area, 0.00064516)
        add(["yd2", "sqyd", "squareyard", "squareyards"], .area, 0.83612736)
        add(["mi2", "sqmi", "squaremile", "squaremiles"], .area, 2589988.110336)
        // data, in bytes: B is a byte and b a bit
        add(["B", "byte", "bytes"], .data, 1)
        add(["b", "bit", "bits"], .data, 0.125)
        for (i, p) in ["K", "M", "G", "T", "P"].enumerated() {
            add(["\(p)B", "\(p.lowercased())B"], .data, pow(1000, Double(i + 1)))
            add(["\(p)iB"], .data, pow(1024, Double(i + 1)))
            add(["\(p)b", "\(p.lowercased())b"], .data, pow(1000, Double(i + 1)) / 8)
        }
        add(["kB"], .data, 1000)
        // energy, in joules
        add(["J", "joule", "joules"], .energy, 1)
        add(["kJ", "kilojoule", "kilojoules"], .energy, 1000)
        add(["cal", "calorie", "calories"], .energy, 4.184)
        add(["kcal", "Cal", "kilocalorie", "kilocalories"], .energy, 4184)
        add(["Wh"], .energy, 3600)
        add(["kWh"], .energy, 3.6e6)
        add(["eV", "electronvolt", "electronvolts"], .energy, 1.602176634e-19)
        add(["BTU", "btu"], .energy, 1055.05585262)
        // power, in watts
        add(["W", "watt", "watts"], .power, 1)
        add(["kW", "kilowatt", "kilowatts"], .power, 1000)
        add(["MW", "megawatt", "megawatts"], .power, 1e6)
        add(["hp", "horsepower"], .power, 745.69987158227)
        // pressure, in pascals
        add(["Pa", "pascal", "pascals"], .pressure, 1)
        add(["kPa", "kilopascal", "kilopascals"], .pressure, 1000)
        add(["MPa", "megapascal"], .pressure, 1e6)
        add(["bar", "bars"], .pressure, 1e5)
        add(["mbar", "millibar"], .pressure, 100)
        add(["atm", "atmosphere", "atmospheres"], .pressure, 101325)
        add(["psi"], .pressure, 6894.757293168)
        add(["mmHg"], .pressure, 133.322387415)
        add(["torr"], .pressure, 101325.0 / 760)
        // force, in newtons
        add(["N", "newton", "newtons"], .force, 1)
        add(["kN", "kilonewton"], .force, 1000)
        add(["lbf"], .force, 4.4482216152605)
        add(["kgf"], .force, 9.80665)
        add(["dyn", "dyne"], .force, 1e-5)
        // angle, in radians
        add(["rad", "radian", "radians"], .angle, 1)
        add(["deg", "degree", "degrees", "°"], .angle, Double.pi / 180)
        add(["grad", "gradian", "gradians"], .angle, Double.pi / 200)
        add(["turn", "turns", "rev", "revolution", "revolutions"], .angle, 2 * Double.pi)
        add(["arcmin", "′"], .angle, Double.pi / 10800)
        add(["arcsec", "″"], .angle, Double.pi / 648000)
        // frequency, in hertz
        add(["Hz", "hz", "hertz"], .frequency, 1)
        add(["kHz", "khz"], .frequency, 1e3)
        add(["MHz", "mhz"], .frequency, 1e6)
        add(["GHz", "ghz"], .frequency, 1e9)
        add(["rpm"], .frequency, 1.0 / 60)
        return t
    }()

    // Temperatures, to and from kelvin.
    private static let temperatures: [String: (name: String, toKelvin: (Double) -> Double, fromKelvin: (Double) -> Double)] = {
        let celsius: (name: String, toKelvin: (Double) -> Double, fromKelvin: (Double) -> Double) = ("°C", { $0 + 273.15 }, { $0 - 273.15 })
        let fahrenheit: (name: String, toKelvin: (Double) -> Double, fromKelvin: (Double) -> Double) = ("°F", { ($0 - 32) * 5 / 9 + 273.15 }, { ($0 - 273.15) * 9 / 5 + 32 })
        let kelvin: (name: String, toKelvin: (Double) -> Double, fromKelvin: (Double) -> Double) = ("K", { $0 }, { $0 })
        return ["c": celsius, "°c": celsius, "degc": celsius, "celsius": celsius, "f": fahrenheit, "°f": fahrenheit, "degf": fahrenheit,
                "fahrenheit": fahrenheit, "k": kelvin, "kelvin": kelvin]
    }()

    // A sum or run of quantities of one kind, 5 km + 300 m and 5 ft 10 in, in the target unit or,
    // where there is none, in the smallest of those given.
    static func parseSum(_ text: String, target: String?) -> Conversion? {
        guard let regex = try? NSRegularExpression(pattern: "([+-]?)\\s*([0-9]+(?:\\.[0-9]+)?)\\s*([A-Za-z°µ][A-Za-z°µ0-9/²³]*)") else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return nil }
        // Nothing else but the joining: + and, commas and spaces.
        var rest = text
        for m in matches.reversed() { rest = (rest as NSString).replacingCharacters(in: m.range, with: "|") }
        guard rest.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "and", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " ,+")).isEmpty else { return nil }
        var terms: [(amount: Double, unit: Unit, name: String)] = []
        for m in matches {
            let sign = ns.substring(with: m.range(at: 1)) == "-" ? -1.0 : 1.0
            let name = ns.substring(with: m.range(at: 3))
            guard let amount = Double(ns.substring(with: m.range(at: 2))), let u = unit(name), u.kind != .temperature else { return nil }
            terms.append((sign * amount, u, name))
        }
        guard let kind = terms.first?.unit.kind, terms.allSatisfy({ $0.unit.kind == kind }) else { return nil }
        let chosen: (unit: Unit, name: String)
        if let target {
            guard let u = unit(target), u.kind == kind else { return nil }
            chosen = (u, target)
        } else {
            let smallest = terms.min { $0.unit.factor < $1.unit.factor }!
            chosen = (smallest.unit, smallest.name)
        }
        let total = terms.reduce(0.0) { $0 + $1.amount * $1.unit.factor } / chosen.unit.factor
        let value = Double(String(format: "%.12g", total)) ?? total
        let given = terms.map { "\(decimal(abs($0.amount))) \($0.name)" }
        var written = given[0]
        for (i, term) in terms.enumerated().dropFirst() { written += (term.amount < 0 ? " − " : " + ") + given[i] }
        var d = Details(name: "", equation: t(text.trimmingCharacters(in: .whitespaces)), steps: [], solutions: [t("= \(decimal(value)) \(chosen.name)")], note: nil, f: { _ in .nan }, roots: [])
        for term in terms {
            d.steps.append(Step(label: "Converting \(decimal(abs(term.amount))) \(term.name) to \(chosen.name)",
                                math: t("\(term.amount < 0 ? "−" : "")\(decimal(abs(term.amount) * term.unit.factor / chosen.unit.factor)) \(chosen.name)")))
        }
        d.steps.append(Step(label: "Adding", math: t("= \(decimal(value)) \(chosen.name)")))
        return Conversion(value: value, text: "= \(decimal(value)) \(chosen.name)", approx: written, details: d)
    }

    // 5'7, 5'7", 5' 7 in and 5': feet and inches as a height is written, read as 5 ft 7 in, and in
    // metres where nothing else is asked. ′ and ″ stay minutes and seconds of arc.
    static func parseFeet(_ text: String) -> Conversion? {
        let pattern = "^([0-9]+(?:\\.[0-9]+)?)\\s*['’]\\s*(?:([0-9]+(?:\\.[0-9]+)?)\\s*(?:\"|”|''|’’|inches|inch|in)?)?\\s*(?:(?:to|in|into|as|->|→|=>)\\s*(\\S.*))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        let written = "\(group(1)!) ft" + (group(2).map { " \($0) in" } ?? "")
        let target = group(3)?.trimmingCharacters(in: .whitespaces) ?? "m"
        // One quantity alone is no sum, so it goes the way 5 ft to m would.
        return group(2) == nil ? parse("\(written) to \(target)") : parseSum(written, target: target)
    }

    // Whether it names a unit, or a temperature scale.
    static func knows(_ typed: String) -> Bool { unit(typed) != nil || temperature(typed) != nil }

    private static func normal(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3").replacingOccurrences(of: "^2", with: "2").replacingOccurrences(of: "^3", with: "3")
            .replacingOccurrences(of: "per", with: "/")
    }

    // A unit by its name as typed: exactly, then without regard to case, so that MB is not mb and
    // l is a litre.
    private static func unit(_ typed: String) -> Unit? {
        let key = normal(typed)
        if let u = table[key] { return u }
        let lower = key.lowercased()
        if let u = table[lower] { return u }
        if let u = table.first(where: { $0.key.lowercased() == lower })?.value, key.count > 2 { return u }
        return nil
    }

    private static func temperature(_ typed: String) -> (name: String, toKelvin: (Double) -> Double, fromKelvin: (Double) -> Double)? {
        let key = normal(typed).lowercased().replacingOccurrences(of: "degrees", with: "deg")
        return temperatures[key]
    }

    static func parse(_ text: String) -> Conversion? {
        // Each place a connector may be, the last first, so that 5 in to cm is five inches.
        var splits: [Range<String.Index>] = []
        for word in [" to ", " in ", " into ", " as ", "->", "→", "=>"] {
            var from = text.startIndex
            while let r = text.range(of: word, options: .caseInsensitive, range: from..<text.endIndex) {
                splits.append(r)
                from = text.index(after: r.lowerBound)
            }
        }
        for split in splits.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            if let c = parse(left: String(text[..<split.lowerBound]), target: String(text[split.upperBound...]).trimmingCharacters(in: .whitespaces), text: text) { return c }
        }
        return nil
    }

    private static func parse(left: String, target: String, text: String) -> Conversion? {
        guard !target.isEmpty, target.count <= 24 else { return nil }
        // 5 km + 300 m to miles, and 5 ft 10 in to cm: several quantities of one kind.
        if let sum = parseSum(left, target: target) { return sum }
        // Where the unit begins in what is on the left: the first place from which what remains is
        // one, and what comes before it is a sum.
        let chars = Array(left)
        for i in chars.indices where i > 0 {
            let c = chars[i]
            guard c.isLetter || "°µ′″".contains(c), chars[i - 1].isNumber || chars[i - 1] == " " || chars[i - 1] == ")" || chars[i - 1] == "." else { continue }
            let head = String(chars[..<i]), tail = String(chars[i...])
            guard !head.trimmingCharacters(in: .whitespaces).isEmpty,
                  let expr = try? Parser.constant(head), !expr.hasUnknown, expr.eval(0).isFinite else { continue }
            let amount = expr.eval(0)
            if let from = temperature(tail), let to = temperature(target) {
                return built(amount, expr, from: (tail, from.toKelvin), to: (target, to.fromKelvin), fromName: from.name, toName: to.name, text: text, temperature: true)
            }
            if let from = unit(tail), let to = unit(target), from.kind == to.kind {
                return built(amount, expr, from: (tail, { $0 * from.factor }), to: (target, { $0 / to.factor }), fromName: tail.trimmingCharacters(in: .whitespaces),
                             toName: target, text: text, temperature: false, factors: (from.factor, to.factor))
            }
            // Units made of others: 17 cm s⁻¹ to m s⁻¹, 9.8 m/s² to cm s^-2, 1000 kg m^-3 to g/cm3.
            guard let (from, to) = compound(tail, target) else { continue }
            // Written as typed where it was typed with a slash (cm/s), and with its powers raised where they were typed in a line (cms^-1, cm s⁻¹).
            func written(_ typed: String, _ r: Reading) -> String { typed.contains("/") ? typed.trimmingCharacters(in: .whitespaces) : r.name }
            return built(amount, expr, from: (tail, { $0 * from.factor }), to: (target, { $0 / to.factor }), fromName: written(tail, from),
                         toName: written(target, to), text: text, temperature: false, factors: (from.factor, to.factor))
        }
        return nil
    }

    // MARK: Units made of others

    // A unit's dimensions: the powers of length, mass, time, angle and data it is made of.
    struct Dimension: Equatable {
        var l = 0, m = 0, t = 0, a = 0, d = 0
        static func + (x: Dimension, y: Dimension) -> Dimension { Dimension(l: x.l + y.l, m: x.m + y.m, t: x.t + y.t, a: x.a + y.a, d: x.d + y.d) }
        static func * (x: Dimension, k: Int) -> Dimension { Dimension(l: x.l * k, m: x.m * k, t: x.t * k, a: x.a * k, d: x.d * k) }
        var isNone: Bool { self == Dimension() }
    }

    // Each kind's dimensions, and how many SI units its base is: a litre is a thousandth of a cubic metre.
    private static func dimension(_ kind: Kind) -> (Dimension, Double)? {
        switch kind {
        case .length: return (Dimension(l: 1), 1)
        case .mass: return (Dimension(m: 1), 1)
        case .time: return (Dimension(t: 1), 1)
        case .volume: return (Dimension(l: 3), 1e-3)
        case .area: return (Dimension(l: 2), 1)
        case .speed: return (Dimension(l: 1, t: -1), 1)
        case .force: return (Dimension(l: 1, m: 1, t: -2), 1)
        case .energy: return (Dimension(l: 2, m: 1, t: -2), 1)
        case .power: return (Dimension(l: 2, m: 1, t: -3), 1)
        case .pressure: return (Dimension(l: -1, m: 1, t: -2), 1)
        case .frequency: return (Dimension(t: -1), 1)
        case .angle: return (Dimension(a: 1), 1)
        case .data: return (Dimension(d: 1), 1)
        case .temperature: return nil
        }
    }

    // One way of reading a unit made of others: how many SI units it is, its dimensions, how it is written
    // (cm s⁻¹), and how many units it was read as.
    struct Reading { var factor: Double; var dimension: Dimension; var name: String; var pieces: Int }

    // Every way of reading what was typed as units multiplied and divided, each with a power: cm/s, cm s^-1,
    // cms⁻¹, kg m^-3, m/s². Letters run together are split into units every way they can be, ms⁻¹ as
    // metres per second and as per millisecond; which is meant is settled by the other side.
    static func readings(_ typed: String) -> [Reading] {
        var text = typed.trimmingCharacters(in: .whitespaces)
        let raised: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
        var plain = ""
        var inPower = false
        for c in text {
            if let d = raised[c] { if !inPower { plain.append("^"); inPower = true }; plain.append(d) } else { inPower = false; plain.append(c) }
        }
        text = plain.replacingOccurrences(of: "·", with: " ").replacingOccurrences(of: "*", with: " ").replacingOccurrences(of: " per ", with: "/")
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 3, !parts.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return [] }
        var chunks: [(letters: String, power: Int)] = []
        for (k, part) in parts.enumerated() {
            for chunk in part.split(separator: " ") {
                let piece = String(chunk) as NSString
                guard let m = chunkPattern.firstMatch(in: piece as String, range: NSRange(location: 0, length: piece.length)),
                      m.range.length == piece.length else { return [] }
                let power = m.range(at: 2).location == NSNotFound ? 1 : Int(piece.substring(with: m.range(at: 2))) ?? 1
                chunks.append((piece.substring(with: m.range(at: 1)), power * (k == 0 ? 1 : -1)))
            }
        }
        guard !chunks.isEmpty, chunks.count <= 6 else { return [] }
        // Each run of letters split into units every way it can be; its power belongs to the last.
        func splits(_ s: String) -> [[(Unit, String)]] {
            if s.isEmpty { return [[]] }
            var out: [[(Unit, String)]] = []
            for n in 1...min(s.count, 14) {
                let head = String(s.prefix(n))
                guard table[head] != nil || (head.count > 2 && unit(head) != nil), let u = unit(head) else { continue }
                for rest in splits(String(s.dropFirst(n))) where out.count < 16 { out.append([(u, head)] + rest) }
            }
            return out
        }
        var results = [Reading(factor: 1, dimension: Dimension(), name: "", pieces: 0)]
        for chunk in chunks {
            var next: [Reading] = []
            for split in splits(chunk.letters) {
                var r = Reading(factor: 1, dimension: Dimension(), name: "", pieces: 0)
                var ok = true
                for (i, (u, written)) in split.enumerated() {
                    guard let (dim, scale) = dimension(u.kind) else { ok = false; break }
                    let power = i == split.count - 1 ? chunk.power : 1
                    r.factor *= pow(u.factor * scale, Double(power))
                    r.dimension = r.dimension + dim * power
                    r.name += (r.name.isEmpty ? "" : " ") + written + (power == 1 ? "" : Units.raised(power))
                    r.pieces += 1
                }
                guard ok else { continue }
                for before in results where next.count < 64 {
                    next.append(Reading(factor: before.factor * r.factor, dimension: before.dimension + r.dimension,
                                        name: before.name.isEmpty ? r.name : before.name + " " + r.name, pieces: before.pieces + r.pieces))
                }
            }
            results = next
            if results.isEmpty { return [] }
        }
        return results
    }

    private static let chunkPattern = try! NSRegularExpression(pattern: "([A-Za-zµÅ°]+)\\^?(-?[0-9]+)?")

    private static func raised(_ n: Int) -> String {
        let signs: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
        return String(String(n).map { signs[$0] ?? $0 })
    }

    // The two sides read alike, of the same dimensions; of the ways that are, the one in fewest units.
    static func compound(_ from: String, _ to: String) -> (Reading, Reading)? {
        let a = readings(from), b = readings(to)
        var best: (Reading, Reading)?
        for x in a where !x.dimension.isNone {
            for y in b where y.dimension == x.dimension {
                if best.map({ x.pieces + y.pieces < $0.0.pieces + $0.1.pieces }) ?? true { best = (x, y) }
            }
        }
        return best
    }

    private static func built(_ amount: Double, _ expr: Expr, from: (String, (Double) -> Double), to: (String, (Double) -> Double),
                              fromName: String, toName: String, text: String, temperature: Bool, factors: (Double, Double)? = nil) -> Conversion {
        let base = from.1(amount)
        let v = to.1(base)
        // Rounded as the card is: 12.000000000000002 inches is 12.
        let value = Double(String(format: "%.12g", v)) ?? v
        let shown = "= \(decimal(value)) \(toName)"
        let amountText = decimal(amount)
        var d = Details(name: "", equation: t("\(amountText) \(fromName) → \(toName)"), steps: [], solutions: [t(shown)], note: nil, f: { _ in .nan }, roots: [])
        if temperature {
            d.steps.append(Step(label: "Converting to kelvin", math: t("\(amountText) \(fromName) = \(decimal(Double(String(format: "%.12g", base)) ?? base)) K")))
            d.steps.append(Step(label: "Converting from kelvin", math: t("\(decimal(Double(String(format: "%.12g", base)) ?? base)) K = \(decimal(value)) \(toName)")))
        } else if let (f, g) = factors {
            d.steps.append(Step(label: "Using the size of each unit", math: t("1 \(fromName) = \(decimal(f / g)) \(toName)"),
                                note: f / g == 1 ? nil : "Both units are measured against the same base unit; the ratio of their sizes is \(decimal(f / g))."))
            d.steps.append(Step(label: "Multiplying", math: t("\(amountText) × \(decimal(f / g)) = \(decimal(value)) \(toName)")))
        }
        d.steps.append(Step(label: "Hence", math: t("\(amountText) \(fromName) = \(decimal(value)) \(toName)")))
        return Conversion(value: value, text: shown, approx: "\(amountText) \(fromName)", details: d)
    }
}


// 0.75 to fraction, 1/3 to decimal, 12345 to scientific, 0.25 to percent, 2024 to roman, MCMXCIV to number.
enum NumberForms {
    static func parse(_ text: String) -> Conversion? {
        guard let m = text.range(of: "\\s+(?:to|in|as|into)\\s+(fraction|decimal|scientific|sci|percent|percentage|roman|arabic|number|integer)\\s*$", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let target = text[m].trimmingCharacters(in: .whitespaces).split(separator: " ").last!.lowercased()
        let quantity = String(text[..<m.lowerBound]).trimmingCharacters(in: .whitespaces)
        // From Roman numerals.
        if ["arabic", "number", "decimal", "integer"].contains(target), let n = fromRoman(quantity) {
            return result(value: Double(n), shown: "= \(n)", approx: "\(quantity.uppercased()) in Roman numerals", copy: String(n), in: text)
        }
        guard let expr = try? Parser.constant(quantity), !expr.hasUnknown, case let v = expr.eval(0), v.isFinite else { return nil }
        switch target {
        case "fraction":
            guard let (p, q) = rational(v), v != v.rounded() else { return nil }
            return result(value: v, shown: "= \(fraction(p, q))", approx: "≈ \(decimal(v))", copy: "\(p)/\(q)", in: text)
        case "decimal":
            guard v != v.rounded() || quantity.contains("/") else { return nil }
            return result(value: v, shown: "\(isExact(v) ? "=" : "≈") \(decimal(v))", approx: nil, copy: String(format: "%.12g", v), in: text)
        case "scientific", "sci":
            guard v != 0 else { return nil }
            let parts = String(format: "%.\(Options.figures - 1)e", v).split(separator: "e")
            guard parts.count == 2, let exponent = Int(parts[1]) else { return nil }
            var mantissa = String(parts[0])
            if mantissa.contains(".") { while mantissa.hasSuffix("0") { mantissa.removeLast() }; if mantissa.hasSuffix(".") { mantissa.removeLast() } }
            return result(value: v, shown: "= \(mantissa.replacingOccurrences(of: "-", with: "−"))×10\(exponent < 0 ? "⁻" : "")\(superscript(abs(exponent)))", approx: nil, copy: String(format: "%.\(Options.figures - 1)e", v), in: text)
        case "percent", "percentage":
            return result(value: v * 100, shown: "= \(decimal(v * 100))%", approx: nil, copy: String(format: "%.12g", v * 100), in: text)
        case "roman":
            guard v == v.rounded(), let n = Int(fitting: v), (1...3999).contains(n) else { return nil }
            let r = roman(n)
            return result(value: v, shown: r, approx: "Roman numerals, for 1 to 3999", copy: r, in: text)
        default: return nil
        }
    }

    private static func result(value: Double, shown: String, approx: String?, copy: String, in text: String) -> Conversion {
        var d = Details(name: "", equation: t(text), steps: [Step(label: "Writing it in the other form", math: t(shown))], solutions: [t(shown)], note: nil, f: { _ in .nan }, roots: [])
        if let approx { d.solutions.append(t(approx)) }
        var c = Conversion(value: value, text: shown, approx: approx, details: d)
        c.copy = copy
        return c
    }

    private static let numerals: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]

    static func roman(_ n: Int) -> String {
        var n = n, out = ""
        for (value, symbol) in numerals { while n >= value { out += symbol; n -= value } }
        return out
    }

    // A Roman numeral written as it is: the number, or nil where it is not one.
    static func fromRoman(_ s: String) -> Int? {
        let upper = s.uppercased()
        guard !upper.isEmpty, upper.allSatisfy({ "MDCLXVI".contains($0) }) else { return nil }
        var total = 0, rest = Substring(upper)
        for (value, symbol) in numerals { while rest.hasPrefix(symbol) { total += value; rest = rest.dropFirst(symbol.count) } }
        return rest.isEmpty && roman(total) == upper ? total : nil
    }
}
