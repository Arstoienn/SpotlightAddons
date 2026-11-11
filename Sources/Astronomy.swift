import Foundation

// Astronomy mode: what follows @ is an astronomical calculation, a function of bodies and values,
// @ escape_velocity(earth), @ orbital_period(1 AU, sun), @ wien_peak(5778 K). Each is answered with
// its working, as a question of the IB Physics course would be: the values taken, the formula, the
// values written in, the answer to three significant figures, which is as many as the data have.
//
// Completion (Completion.swift) offers the functions as @ is typed, and the bodies and units that
// fit each argument inside the brackets; this file is what it offers and what is worked out.
struct Astronomy {
    var solution: Solution
    var details: Details?
    var copy: String?
    var value: Double?

    static let catalogue = AstronomyCatalogue()

    // Astronomy is asked for: the mark typed first, and the mode on.
    static func marked(_ typed: String) -> Bool {
        Options.astronomy && typed.drop(while: { $0 == " " }).first == "@"
    }

    // The answer to a call, or nil while it is still being typed: no name yet, a placeholder still
    // standing, an argument half written. A call that is closed and still cannot be answered says why.
    static func parse(_ typed: String) -> Astronomy? {
        guard marked(typed) else { return nil }
        let text = String(typed.drop(while: { $0 == " " }).dropFirst()).trimmingCharacters(in: .whitespaces)
        let natural = text.range(of: "^[A-Za-z_]+\\s+escape\\s+(speed|velocity)$", options: [.regularExpression, .caseInsensitive]) != nil
        if natural { return AstronomyEngine.shared.answer(typed) }
        if let opening = text.firstIndex(of: "(") {
            let name = text[..<opening].trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
            if let method = AstronomyEngine.methods.first(where: { $0.name == name || $0.aliases.contains(name) }) {
                guard text.hasSuffix(")") else { return nil }
                let inside = String(text[text.index(after: opening)..<text.index(before: text.endIndex)])
                let arguments = topLevel(inside)
                // Completion placeholders never enter the numerical worker.
                if arguments.contains(where: { arg in method.parameters.contains { $0.name == arg.trimmingCharacters(in: .whitespaces) } }) { return nil }
                return AstronomyEngine.shared.answer(typed)
            }
        }
        guard let open = text.firstIndex(of: "(") else { return nil }
        let typedName = text[..<open].trimmingCharacters(in: .whitespaces)
        var inside = String(text[text.index(after: open)...])
        let closed = inside.hasSuffix(")")
        if closed { inside.removeLast() }
        // A call closed is finished; one left open at the end is answered too, when it reads.
        func failed(_ exact: String, _ approx: String) -> Astronomy? {
            closed ? Astronomy(solution: Solution(exact: exact, approx: approx)) : nil
        }
        let wanted = typedName.lowercased().replacingOccurrences(of: " ", with: "_")
        guard let function = AstronomyCatalogue.table.first(where: { $0.function.name == wanted || $0.function.aliases.contains(wanted) }) else {
            return failed("No such function: \(typedName)", "Type @ to see the functions there are")
        }
        let arguments = topLevel(inside).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !arguments.contains(where: \.isEmpty) || arguments == [""] else { return nil }
        guard arguments != [""] else { return failed("Nothing given to \(function.function.name)", "It takes \(signature(function.function))") }
        guard let formIndex = function.function.forms.firstIndex(where: { $0.count == arguments.count }) else {
            return failed("\(function.function.name) takes \(signature(function.function))", "\(arguments.count) given")
        }
        let form = function.function.forms[formIndex]
        var resolved: [Argument] = []
        for (argument, parameter) in zip(arguments, form) {
            if argument == parameter.name { return nil }   // a placeholder not yet typed over
            guard let value = Argument.read(argument, as: parameter.kind) else {
                return failed("Not \(Kind.of(parameter.kind).title): \(argument)", "Expected \(Kind.of(parameter.kind).title) for \(parameter.name)")
            }
            resolved.append(value)
        }
        do {
            return try function.work(formIndex, resolved).answer
        } catch let problem as Problem {
            return failed(problem.message, problem.detail)
        } catch {
            return nil
        }
    }

    static func signature(_ f: Completion.Function) -> String {
        f.forms.map { "(" + $0.map(\.name).joined(separator: ", ") + ")" }.joined(separator: " or ")
    }

    // Arguments split at the commas not inside brackets of their own.
    static func topLevel(_ s: String) -> [String] {
        var parts: [String] = [], current = "", depth = 0
        var quote: Character?, escaped = false
        for c in s {
            if let q = quote {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == q { quote = nil }
            } else if c == "\"" || c == "'" { quote = c }
            else if "([{".contains(c) { depth += 1 }
            else if ")]}".contains(c) { depth -= 1 }
            if c == ",", depth == 0, quote == nil { parts.append(current); current = "" } else { current.append(c) }
        }
        parts.append(current)
        return parts
    }
}

struct Problem: Error {
    var message: String
    var detail: String
}

// MARK: - Quantities

enum Dimension {
    case mass, length, time, temperature, power, angle, speed, none
}

struct AstroUnit {
    var symbol: String          // as written: M☉, km, AU
    var name: String            // in words, for the list: solar masses
    var factor: Double          // in SI units (the radian for an angle)
    var dimension: Dimension
    var keys: [String] = []     // other ways of typing it: Msun, solar mass
    var offset: Double = 0      // added after the factor: °C to kelvin

    static let arcsecond = Double.pi / 648_000

    // The IB data booklet's values where it gives them, to three significant figures.
    static let all: [AstroUnit] = [
        AstroUnit(symbol: "M☉", name: "solar masses", factor: Body.solarMass, dimension: .mass, keys: ["Msun", "M_sun", "Msol", "solar mass", "solar masses"]),
        AstroUnit(symbol: "M⊕", name: "Earth masses", factor: 5.97e24, dimension: .mass, keys: ["Mearth", "M_earth", "earth mass", "earth masses"]),
        AstroUnit(symbol: "M_J", name: "Jupiter masses", factor: 1.90e27, dimension: .mass, keys: ["MJ", "Mjup", "M_jup", "jupiter mass", "jupiter masses"]),
        AstroUnit(symbol: "kg", name: "kilograms", factor: 1, dimension: .mass),
        AstroUnit(symbol: "g", name: "grams", factor: 1e-3, dimension: .mass),
        AstroUnit(symbol: "t", name: "tonnes", factor: 1e3, dimension: .mass),
        AstroUnit(symbol: "AU", name: "astronomical units", factor: 1.50e11, dimension: .length, keys: ["au"]),
        AstroUnit(symbol: "km", name: "kilometres", factor: 1e3, dimension: .length),
        AstroUnit(symbol: "m", name: "metres", factor: 1, dimension: .length),
        AstroUnit(symbol: "ly", name: "light years", factor: 9.46e15, dimension: .length, keys: ["light year", "light years"]),
        AstroUnit(symbol: "pc", name: "parsecs", factor: 3.09e16, dimension: .length, keys: ["parsec", "parsecs"]),
        AstroUnit(symbol: "kpc", name: "kiloparsecs", factor: 3.09e19, dimension: .length),
        AstroUnit(symbol: "Mpc", name: "megaparsecs", factor: 3.09e22, dimension: .length),
        AstroUnit(symbol: "R☉", name: "solar radii", factor: 6.96e8, dimension: .length, keys: ["Rsun", "R_sun", "solar radius", "solar radii"]),
        AstroUnit(symbol: "R⊕", name: "Earth radii", factor: 6.37e6, dimension: .length, keys: ["Rearth", "R_earth", "earth radius", "earth radii"]),
        AstroUnit(symbol: "R_J", name: "Jupiter radii", factor: 6.99e7, dimension: .length, keys: ["RJ", "Rjup", "R_jup"]),
        AstroUnit(symbol: "nm", name: "nanometres", factor: 1e-9, dimension: .length),
        AstroUnit(symbol: "μm", name: "micrometres", factor: 1e-6, dimension: .length, keys: ["um", "µm"]),
        AstroUnit(symbol: "mm", name: "millimetres", factor: 1e-3, dimension: .length),
        AstroUnit(symbol: "Å", name: "ångströms", factor: 1e-10, dimension: .length, keys: ["angstrom", "angstroms"]),
        AstroUnit(symbol: "K", name: "kelvin", factor: 1, dimension: .temperature),
        AstroUnit(symbol: "°C", name: "degrees Celsius", factor: 1, dimension: .temperature, keys: ["C", "degC"], offset: 273.15),
        AstroUnit(symbol: "L☉", name: "solar luminosities", factor: Body.solarLuminosity, dimension: .power, keys: ["Lsun", "L_sun", "solar luminosity", "solar luminosities"]),
        AstroUnit(symbol: "W", name: "watts", factor: 1, dimension: .power),
        AstroUnit(symbol: "arcsec", name: "seconds of arc", factor: arcsecond, dimension: .angle, keys: ["″", "\"", "as", "arcsecond", "arcseconds"]),
        AstroUnit(symbol: "mas", name: "milliarcseconds", factor: arcsecond / 1000, dimension: .angle, keys: ["milliarcsec", "milliarcseconds"]),
        AstroUnit(symbol: "arcmin", name: "minutes of arc", factor: arcsecond * 60, dimension: .angle, keys: ["′", "'"]),
        AstroUnit(symbol: "°", name: "degrees", factor: Double.pi / 180, dimension: .angle, keys: ["deg", "degrees"]),
        AstroUnit(symbol: "s", name: "seconds", factor: 1, dimension: .time),
        AstroUnit(symbol: "days", name: "days", factor: 86_400, dimension: .time, keys: ["day", "d"]),
        AstroUnit(symbol: "years", name: "years", factor: 3.156e7, dimension: .time, keys: ["year", "yr", "y"]),
        AstroUnit(symbol: "km s⁻¹", name: "kilometres per second", factor: 1e3, dimension: .speed, keys: ["km/s", "km s^-1", "kms^-1"]),
        AstroUnit(symbol: "m s⁻¹", name: "metres per second", factor: 1, dimension: .speed, keys: ["m/s", "m s^-1", "ms^-1"]),
    ]

    // A number with a unit, or with none: 10 M☉, 1.5e11 m, 0.772″, 5778 K.
    static func quantity(_ text: String) -> (value: Double, unit: AstroUnit?)? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if let n = number(s) { return (n, nil) }
        // The longest unit the text ends with, exactly as written, and then in any case, as long
        // as the rest is a number: Mpc is not mpc, but msun is Msun.
        let spellings = all.flatMap { u in ([u.symbol] + u.keys).map { (u, $0, $0 == u.symbol) } }.sorted { $0.1.count > $1.1.count }
        for exact in [true, false] {
            // In any case only the other spellings, and not a symbol: Mpc is never mpc.
            for (unit, spelling, symbol) in spellings where exact || (!symbol && spelling.count > 2) {
                let ends = exact ? s.hasSuffix(spelling) : s.lowercased().hasSuffix(spelling.lowercased())
                guard ends else { continue }
                let rest = String(s.dropLast(spelling.count)).trimmingCharacters(in: .whitespaces)
                if let n = number(rest) { return (n, unit) }
            }
        }
        return nil
    }

    // 1.5e11, 1.5×10^11, 1.5×10¹¹, 2*10^30, −1.46, and anything else that works out to a number.
    static func number(_ text: String) -> Double? {
        let s = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: " ", with: "")
        guard !s.isEmpty else { return nil }
        if let n = Double(s), n.isFinite, s.first != "+" || s.count > 1 { return n }
        // m×10^k with the power written either way.
        let superscripts: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
        if let m = s.range(of: "^([-+]?[0-9.]+)[×x*]10(\\^?)([-+⁻]?[0-9⁰-⁹]+)$", options: .regularExpression), m.lowerBound == s.startIndex {
            let parts = s.split(whereSeparator: { "×x*".contains($0) })
            guard parts.count == 2, let mantissa = Double(parts[0]) else { return nil }
            let power = String(parts[1].dropFirst(2).filter { $0 != "^" }.map { superscripts[$0] ?? $0 })
            guard let k = Double(power) else { return nil }
            return mantissa * pow(10, k)
        }
        // Only arithmetic: a letter here is a unit or a body, not something to work out.
        guard !s.contains(where: { $0.isLetter && $0 != "e" }), let expr = try? Parser.constant(s, physical: false), !expr.hasUnknown else { return nil }
        let v = expr.eval(0)
        return v.isFinite ? v : nil
    }
}

// MARK: - Bodies

struct Body {
    var id: String              // as typed: earth, alpha_centauri
    var name: String            // in a sentence: the Earth
    var kind: String            // star, planet, moon, dwarf planet, black hole
    var mass: Double
    var radius: Double?
    var orbit: (around: String, a: Double)? = nil
    var temperature: Double? = nil
    var luminosity: Double? = nil
    var parallax: Double? = nil     // in seconds of arc, as measured
    var distance: Double? = nil     // from the Earth, where there is no parallax to give it
    var apparent: Double? = nil     // apparent magnitude
    var keys: [String] = []

    static let solarMass = 1.99e30, solarRadius = 6.96e8, solarLuminosity = 3.83e26
    static let au = 1.50e11, parsec = 3.09e16, lightYear = 9.46e15

    var possessive: String { name + "’s" }
    var title: String { name.hasPrefix("the ") ? name.prefix(1).uppercased() + name.dropFirst() : name }
    // From the Earth: by its parallax where it has one, d = 1/p.
    var distanceFromEarth: Double? { parallax.map { Body.parsec / $0 } ?? distance }
    var absolute: Double? {
        guard let m = apparent, let d = distanceFromEarth else { return nil }
        return m - 5 * log10(d / (10 * Body.parsec))
    }
    var primary: Body? { orbit.flatMap { o in Body.all.first { $0.id == o.around } } }
    var density: Double? { radius.map { mass / (4.0 / 3.0 * Double.pi * pow($0, 3)) } }

    // The Sun, the planets and the Moon from NASA's fact sheets and the IB data booklet, and a few
    // stars, with a black hole: each with what is known of it to three significant figures.
    static let all: [Body] = [
        Body(id: "sun", name: "the Sun", kind: "star", mass: solarMass, radius: solarRadius, temperature: 5778, luminosity: solarLuminosity,
             distance: au, apparent: -26.74, keys: ["sol", "☉"]),
        Body(id: "mercury", name: "Mercury", kind: "planet", mass: 3.30e23, radius: 2.44e6, orbit: ("sun", 5.79e10)),
        Body(id: "venus", name: "Venus", kind: "planet", mass: 4.87e24, radius: 6.05e6, orbit: ("sun", 1.08e11)),
        Body(id: "earth", name: "the Earth", kind: "planet", mass: 5.97e24, radius: 6.37e6, orbit: ("sun", au), keys: ["⊕", "terra"]),
        Body(id: "moon", name: "the Moon", kind: "moon", mass: 7.35e22, radius: 1.74e6, orbit: ("earth", 3.84e8), keys: ["luna"]),
        Body(id: "mars", name: "Mars", kind: "planet", mass: 6.42e23, radius: 3.39e6, orbit: ("sun", 2.28e11)),
        Body(id: "jupiter", name: "Jupiter", kind: "planet", mass: 1.90e27, radius: 6.99e7, orbit: ("sun", 7.79e11)),
        Body(id: "saturn", name: "Saturn", kind: "planet", mass: 5.68e26, radius: 5.82e7, orbit: ("sun", 1.43e12)),
        Body(id: "uranus", name: "Uranus", kind: "planet", mass: 8.68e25, radius: 2.54e7, orbit: ("sun", 2.87e12)),
        Body(id: "neptune", name: "Neptune", kind: "planet", mass: 1.02e26, radius: 2.46e7, orbit: ("sun", 4.50e12)),
        Body(id: "pluto", name: "Pluto", kind: "dwarf planet", mass: 1.30e22, radius: 1.19e6, orbit: ("sun", 5.91e12)),
        Body(id: "sirius", name: "Sirius A", kind: "star", mass: 2.06 * solarMass, radius: 1.71 * solarRadius, temperature: 9940,
             luminosity: 25.4 * solarLuminosity, parallax: 0.379, apparent: -1.46, keys: ["sirius a", "dog star"]),
        Body(id: "alpha_centauri", name: "Alpha Centauri A", kind: "star", mass: 1.08 * solarMass, radius: 1.22 * solarRadius, temperature: 5790,
             luminosity: 1.52 * solarLuminosity, parallax: 0.747, apparent: 0.01, keys: ["alpha centauri a", "rigil kentaurus", "α centauri"]),
        Body(id: "proxima", name: "Proxima Centauri", kind: "star", mass: 0.122 * solarMass, radius: 0.154 * solarRadius, temperature: 3042,
             luminosity: 0.00155 * solarLuminosity, parallax: 0.768, apparent: 11.13, keys: ["proxima centauri"]),
        Body(id: "vega", name: "Vega", kind: "star", mass: 2.14 * solarMass, radius: 2.36 * solarRadius, temperature: 9600,
             luminosity: 40.1 * solarLuminosity, parallax: 0.130, apparent: 0.03, keys: ["alpha lyrae"]),
        Body(id: "betelgeuse", name: "Betelgeuse", kind: "star", mass: 16.5 * solarMass, radius: 764 * solarRadius, temperature: 3600,
             luminosity: 1.26e5 * solarLuminosity, parallax: 0.00595, apparent: 0.50, keys: ["alpha orionis"]),
        Body(id: "sgr_a", name: "Sagittarius A*", kind: "black hole", mass: 4.30e6 * solarMass, radius: nil, distance: 8.18e3 * parsec,
             keys: ["sagittarius a", "sgr a*", "black hole", "milky way"]),
    ]

    static func named(_ text: String) -> Body? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        let spaced = s.replacingOccurrences(of: "_", with: " ")
        return all.first { $0.id == s || $0.id.replacingOccurrences(of: "_", with: " ") == spaced || $0.keys.contains(spaced) || $0.name.lowercased() == spaced
            || $0.name.lowercased() == "the " + spaced }
    }
}

// MARK: - What an argument may be

// What each parameter takes, and what a body stands for there: as the mass, the Earth is its mass;
// as the orbit, its distance from the Sun.
struct Kind {
    var title: String                       // "a mass", in "Not a mass: 12 parsecs"
    var dimension: Dimension?               // what a value given must be; nil where only a body will do
    var symbol: String                      // what it is written as in the working
    var fromBody: (Body) -> Double?         // what a body gives here, if it gives anything
    var units: [String] = []                // offered once a number is typed, in this order
    var bare: String? = nil                 // the unit of a number typed with none: kg, m, arcsec

    static func of(_ name: String) -> Kind { table[name] ?? Kind(title: "a " + name.replacingOccurrences(of: "_", with: " "), dimension: nil, symbol: "", fromBody: { _ in nil }) }

    static let table: [String: Kind] = [
        "mass": Kind(title: "a mass", dimension: .mass, symbol: "M", fromBody: { $0.mass }, units: ["M☉", "M⊕", "M_J", "kg"], bare: "kg"),
        "body": Kind(title: "a body with a mass and a radius", dimension: nil, symbol: "", fromBody: { $0.radius == nil ? nil : $0.mass }),
        "satellite": Kind(title: "a body in orbit", dimension: nil, symbol: "", fromBody: { $0.orbit?.a }),
        "star": Kind(title: "a star", dimension: nil, symbol: "", fromBody: { $0.temperature == nil || $0.radius == nil ? nil : $0.luminosity }),
        "seen": Kind(title: "a body with a magnitude", dimension: nil, symbol: "", fromBody: { $0.absolute }),
        "luminous": Kind(title: "a star at a known distance", dimension: nil, symbol: "", fromBody: { $0.luminosity == nil ? nil : $0.distanceFromEarth }),
        "radius": Kind(title: "a radius", dimension: .length, symbol: "R", fromBody: { $0.radius }, units: ["km", "m", "R☉", "R⊕", "R_J"], bare: "m"),
        "orbit": Kind(title: "an orbital radius", dimension: .length, symbol: "a", fromBody: { $0.orbit?.a }, units: ["AU", "km", "m"], bare: "m"),
        "central": Kind(title: "a mass", dimension: .mass, symbol: "M", fromBody: { $0.mass }, units: ["M☉", "M⊕", "M_J", "kg"], bare: "kg"),
        "temperature": Kind(title: "a temperature", dimension: .temperature, symbol: "T", fromBody: { $0.temperature }, units: ["K", "°C"], bare: "K"),
        "luminosity": Kind(title: "a luminosity", dimension: .power, symbol: "L", fromBody: { $0.luminosity }, units: ["L☉", "W"], bare: "W"),
        "distance": Kind(title: "a distance", dimension: .length, symbol: "d", fromBody: { $0.distanceFromEarth }, units: ["pc", "ly", "AU", "m"], bare: "m"),
        "parallax": Kind(title: "a parallax angle", dimension: .angle, symbol: "p", fromBody: { $0.parallax.map { $0 * AstroUnit.arcsecond } }, units: ["arcsec", "mas"], bare: "arcsec"),
        "apparent": Kind(title: "an apparent magnitude", dimension: Dimension.none, symbol: "m", fromBody: { $0.apparent }),
        "absolute": Kind(title: "an absolute magnitude", dimension: Dimension.none, symbol: "M", fromBody: { $0.absolute }),
        "redshift": Kind(title: "a redshift", dimension: Dimension.none, symbol: "z", fromBody: { _ in nil }),
        "wavelength": Kind(title: "a wavelength", dimension: .length, symbol: "λ", fromBody: { _ in nil }, units: ["nm", "μm", "m", "Å"], bare: "m"),
    ]
}

// An argument as typed: a body, or a value, in SI units, with how it was written.
enum Argument {
    case body(Body)
    case value(Double, written: String)

    static func read(_ text: String, as kind: String) -> Argument? {
        let k = Kind.of(kind)
        if let body = Body.named(text) { return k.fromBody(body) != nil ? .body(body) : nil }
        guard let dimension = k.dimension, let (n, unit) = AstroUnit.quantity(text) else { return nil }
        if let unit {
            guard unit.dimension == dimension else { return nil }
            return .value(n * unit.factor + unit.offset, written: "\(Format.number(n, figures: 6)) \(unit.symbol)")
        }
        // A bare number is in SI units (a parallax in seconds of arc, as the formula takes it), or is
        // a magnitude or redshift, which have none.
        if let symbol = k.bare, let unit = AstroUnit.all.first(where: { $0.symbol == symbol }) {
            return .value(n * unit.factor + unit.offset, written: "\(Format.number(n, figures: 6)) \(unit.symbol)")
        }
        return .value(n, written: Format.number(n, figures: 6))
    }

    var body: Body? { if case .body(let b) = self { b } else { nil } }
}

// MARK: - Writing numbers

enum Format {
    // To so many significant figures: in full from 0.01 to 9999, in standard form outside that.
    static func number(_ x: Double, figures: Int = 3) -> String {
        guard x.isFinite else { return "∞" }
        guard x != 0 else { return "0" }
        let magnitude = Int(floor(log10(abs(x))))
        let step = pow(10, Double(magnitude - figures + 1))
        let rounded = (x / step).rounded() * step
        let shown: String
        if (-2...3).contains(magnitude), abs(rounded) < 1e4 {
            shown = String(format: "%.\(max(0, figures - 1 - magnitude))f", rounded)
        } else {
            let parts = String(format: "%.\(figures - 1)e", x).split(separator: "e")
            let power = Int(parts[1]) ?? 0
            shown = "\(parts[0])×10\(power < 0 ? "⁻" : "")\(superscript(abs(power)))"
        }
        // Six figures asked for a value typed: no zeros that were never typed.
        var out = shown
        if figures > 3, out.contains("."), !out.contains("×") { while out.hasSuffix("0") { out.removeLast() }; if out.hasSuffix(".") { out.removeLast() } }
        if figures > 3, out.contains("×") {
            let pieces = out.components(separatedBy: "×")
            var mantissa = pieces[0]
            if mantissa.contains(".") { while mantissa.hasSuffix("0") { mantissa.removeLast() }; if mantissa.hasSuffix(".") { mantissa.removeLast() } }
            out = mantissa + "×" + pieces[1]
        }
        return out.replacingOccurrences(of: "-", with: "−")
    }

    // A magnitude: to two decimal places, as catalogues give them.
    static func magnitude(_ x: Double) -> String { String(format: "%.2f", x).replacingOccurrences(of: "-", with: "−") }

    // The same quantity in a unit easier to picture, where there is one: 2950 m as 2.95 km.
    static func alternative(_ x: Double, _ dimension: Dimension) -> (Double, String)? {
        let a = abs(x)
        switch dimension {
        case .length:
            if a < 1e-12 { return nil }
            if a < 1e-6 { return (x / 1e-9, "nm") }
            if a < 1e-3 { return (x / 1e-6, "μm") }
            if a < 1 { return (x / 1e-3, "mm") }
            if a < 1e3 { return nil }
            if a < 1e10 { return (x / 1e3, "km") }
            if a < 1e15 { return (x / Body.au, "AU") }
            return (x / Body.lightYear, "ly")
        case .time:
            if a < 7_200 { return (x / 60, "minutes") }
            if a < 2 * 86_400 { return (x / 3_600, "hours") }
            if a < 2 * 3.156e7 { return (x / 86_400, "days") }
            return (x / 3.156e7, "years")
        case .speed: return a >= 1e3 ? (x / 1e3, "km s⁻¹") : nil
        case .power: return (x / Body.solarLuminosity, "L☉")
        // A star's in solar masses, a planet's in Earth masses.
        case .mass: return a >= 0.01 * Body.solarMass ? (x / Body.solarMass, "M☉") : (x / 5.97e24, "M⊕")
        default: return nil
        }
    }
}

// MARK: - The functions

struct AstronomyCatalogue: Catalogue {
    let mark: Character = "@"
    var functions: [Completion.Function] {
        let methods = AstronomyEngine.methods.map(\.completion)
        let names = Set(methods.flatMap { [$0.name] + $0.aliases })
        return methods + AstronomyCatalogue.table.map(\.function).filter { !names.contains($0.name) }
    }

    struct Entry {
        var function: Completion.Function
        var work: (_ form: Int, _ arguments: [Argument]) throws -> Worked
    }

    // The bodies that fit, then, once a number is typed, that number with each unit that fits.
    func candidates(for parameter: Completion.Parameter, typed: String) -> [Completion.Item] {
        let units: [String: [String]] = [
            "speed": ["m/s", "km/s", "c"], "time": ["s", "day", "yr", "Myr", "Gyr"],
            "angle": ["deg", "rad", "arcsec", "mas"], "frequency": ["Hz", "kHz", "MHz", "GHz", "THz"],
            "length": ["m", "km", "mm", "um", "AU", "pc"], "density": ["kg/m3", "g/cm3"],
            "acceleration": ["m/s2"], "force": ["N"], "mass_flow": ["kg/s", "M_sun/yr"]
        ]
        if let choices = units[parameter.kind],
           let range = typed.range(of: "^[-+−]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?", options: .regularExpression) {
            let n = String(typed[range])
            return choices.map { Completion.Item(title: n + " " + $0, detail: parameter.kind.replacingOccurrences(of: "_", with: " "), insertion: n + " " + $0, remembered: "unit " + $0) }
        }
        var snippets: [Completion.Item] = []
        for method in AstronomyEngine.methods {
            guard let index = method.parameters.firstIndex(where: { $0.name == parameter.name && $0.kind == parameter.kind }),
                  let open = method.example.firstIndex(of: "(") else { continue }
            let args = Astronomy.topLevel(String(method.example[method.example.index(after: open)..<method.example.index(before: method.example.endIndex)]))
            guard index < args.count else { continue }
            let value = args[index].trimmingCharacters(in: .whitespaces)
            if let defaultValue = method.parameters[index].default, parameter.kind.hasPrefix("model_"),
               !snippets.contains(where: { $0.insertion == "\"" + defaultValue + "\"" }) {
                snippets.append(Completion.Item(title: defaultValue, detail: "Model · " + method.name, insertion: "\"" + defaultValue + "\""))
            }
            if !snippets.contains(where: { $0.insertion == value }), !value.contains("=") {
                snippets.append(Completion.Item(title: value, detail: "Example · " + method.name, insertion: value))
            }
        }
        if parameter.kind == "cosmology_model" {
            snippets += ["Planck18", "Planck15", "WMAP9"].map { Completion.Item(title: $0, detail: "Cosmology model", insertion: "\"" + $0 + "\"") }
        }
        let kind = Kind.of(parameter.kind)
        var items = Body.all.compactMap { body -> Completion.Item? in
            guard let v = kind.fromBody(body) else { return nil }
            return Completion.Item(title: body.id, detail: describe(body, kind, v), insertion: body.id,
                                   keys: [body.name, body.name.replacingOccurrences(of: "the ", with: "")] + body.keys)
        }
        let number = typed.range(of: "^\\s*[-+−]?[0-9][0-9.]*(?:[eE][-+]?[0-9]+)?(?:\\s*[×x*]\\s*10\\^?[-+⁻]?[0-9⁰-⁹]*)?", options: .regularExpression)
        if let number {
            let n = typed[number].trimmingCharacters(in: .whitespaces)
            for symbol in kind.units {
                guard let unit = AstroUnit.all.first(where: { $0.symbol == symbol }) else { continue }
                items.append(Completion.Item(title: "\(n) \(unit.symbol)", detail: unit.name, insertion: "\(n) \(unit.symbol)",
                                             keys: ([unit.name] + unit.keys).map { "\(n) \($0)" } + unit.keys.map { "\(n)\($0)" },
                                             remembered: "unit \(unit.symbol)"))
            }
            // Bodies are not numbers: once one is typed only units are offered.
            items.removeAll { !$0.title.hasPrefix(n) }
        }
        for snippet in snippets where !items.contains(where: { $0.insertion == snippet.insertion }) { items.append(snippet) }
        return items
    }

    private func describe(_ body: Body, _ kind: Kind, _ v: Double) -> String {
        let what = body.title + ", " + body.kind
        switch kind.dimension {
        case .mass?: return "\(what) · \(Format.number(v)) kg"
        case .length?: return "\(what) · \(Format.number(v)) m"
        case .temperature?: return "\(what) · \(Format.number(v)) K"
        case .power?: return "\(what) · \(Format.number(v)) W"
        case .angle?: return "\(what) · \(Format.number(v / AstroUnit.arcsecond)) arcsec"
        case Dimension.none?: return "\(what) · \(Format.magnitude(v))"
        default: return what
        }
    }

    private static func p(_ name: String, _ kind: String) -> Completion.Parameter { Completion.Parameter(name: name, kind: kind) }

    static let table: [Entry] = [
        Entry(function: Completion.Function(name: "mass", forms: [[p("body", "mass")]],
                                            summary: "Mass of a body, in kilograms and in Earth or solar masses", aliases: ["mass_of", "weight"]),
              work: Worked.mass),
        Entry(function: Completion.Function(name: "schwarzschild", forms: [[p("body", "mass")]],
                                            summary: "Schwarzschild radius, r_s = 2GM/c²", aliases: ["schwarzschild_radius", "event_horizon", "black_hole"]),
              work: Worked.schwarzschild),
        Entry(function: Completion.Function(name: "escape_velocity", forms: [[p("body", "body")], [p("M", "mass"), p("r", "radius")]],
                                            summary: "Escape speed, v = √(2GM/r)", aliases: ["escape_speed", "v_esc"]),
              work: Worked.escape),
        Entry(function: Completion.Function(name: "surface_gravity", forms: [[p("body", "body")], [p("M", "mass"), p("R", "radius")]],
                                            summary: "Gravitational field strength at the surface, g = GM/R²", aliases: ["gravity", "field_strength"]),
              work: Worked.gravity),
        Entry(function: Completion.Function(name: "orbital_period", forms: [[p("body", "satellite")], [p("a", "orbit"), p("M", "central")]],
                                            summary: "Kepler’s third law, T² = 4π²a³/GM", aliases: ["kepler", "period", "year_length"]),
              work: Worked.period),
        Entry(function: Completion.Function(name: "orbital_speed", forms: [[p("body", "satellite")], [p("a", "orbit"), p("M", "central")]],
                                            summary: "Speed in a circular orbit, v = √(GM/a)", aliases: ["orbital_velocity", "circular_speed"]),
              work: Worked.speed),
        Entry(function: Completion.Function(name: "hill_radius", forms: [[p("body", "satellite")], [p("a", "orbit"), p("m", "mass"), p("M", "central")]],
                                            summary: "Hill sphere, r_H ≈ a ∛(m/3M)", aliases: ["hill_sphere"]),
              work: Worked.hill),
        Entry(function: Completion.Function(name: "roche_limit", forms: [[p("body", "satellite")], [p("primary", "body"), p("satellite", "body")]],
                                            summary: "Roche limit of a rigid satellite, d = R ∛(2ρ_M/ρ_m)", aliases: ["roche"]),
              work: Worked.roche),
        Entry(function: Completion.Function(name: "luminosity", forms: [[p("body", "star")], [p("R", "radius"), p("T", "temperature")]],
                                            summary: "Stefan–Boltzmann law, L = σ4πR²T⁴", aliases: ["stefan_boltzmann", "power"]),
              work: Worked.luminosity),
        Entry(function: Completion.Function(name: "wien_peak", forms: [[p("T", "temperature")]],
                                            summary: "Wien’s displacement law, λ_max = b/T", aliases: ["wien", "peak_wavelength"]),
              work: Worked.wien),
        Entry(function: Completion.Function(name: "parallax_distance", forms: [[p("p", "parallax")]],
                                            summary: "Distance from parallax, d = 1/p", aliases: ["parallax", "distance"]),
              work: Worked.parallax),
        Entry(function: Completion.Function(name: "absolute_magnitude", forms: [[p("body", "seen")], [p("m", "apparent"), p("d", "distance")]],
                                            summary: "M = m − 5 log₁₀(d/10 pc)", aliases: ["abs_mag"]),
              work: Worked.absolute),
        Entry(function: Completion.Function(name: "apparent_magnitude", forms: [[p("M", "absolute"), p("d", "distance")]],
                                            summary: "m = M + 5 log₁₀(d/10 pc)", aliases: ["app_mag", "magnitude"]),
              work: Worked.apparent),
        Entry(function: Completion.Function(name: "apparent_brightness", forms: [[p("body", "luminous")], [p("L", "luminosity"), p("d", "distance")]],
                                            summary: "Inverse-square law, b = L/4πd²", aliases: ["brightness", "flux", "intensity"]),
              work: Worked.brightness),
        Entry(function: Completion.Function(name: "redshift_velocity", forms: [[p("z", "redshift")], [p("λ", "wavelength"), p("λ0", "wavelength")]],
                                            summary: "Recession speed, v ≈ cz with z = Δλ/λ₀", aliases: ["redshift", "doppler", "recession"]),
              work: Worked.redshift),
    ]
}

// MARK: - Working

// A value in the working: its symbol, its value in SI units, and where it came from.
struct Datum {
    var symbol: String
    var value: Double
    var unit: String
    var from: String?          // the Earth’s mass; or the value as it was typed, where that was in other units
    var figures = 3

    var written: String? = nil    // as it is to be shown, where that is not to so many figures: a magnitude
    var bare: String { written ?? Format.number(value, figures: figures) }   // without its unit, as it is written into a formula
    // A magnitude, to two decimal places.
    var magnitude: Datum { var g = self; g.written = Format.magnitude(value); return g }
    var shown: String { bare + (unit.isEmpty ? "" : " " + unit) }
    var line: String {
        guard let from, !from.isEmpty, from != shown, written != from, from != "\(written ?? "") \(unit)" else { return "\(symbol) = \(shown)" }
        // Typed in another unit: 10 M☉ = 1.99×10³¹ kg.
        return from.first?.isNumber == true || from.first == "−" ? "\(symbol) = \(from) = \(shown)" : "\(symbol) = \(shown)"
    }
}

// A function worked out: its answer and the steps to it.
struct Worked {
    var title: String           // Escape velocity of the Earth
    var symbol: String          // v_esc
    var value: Double           // in SI units
    var unit: String            // m s⁻¹
    var dimension: Dimension
    var given: [Datum]
    var sources: String?        // where the values came from
    var formula: Math?          // none for a value looked up, as a mass is
    var substituted: Math?
    var extra: [Step] = []      // steps of its own, before the formula
    var after: [Step] = []      // after the answer: what it means
    var graph: Graph? = nil
    var diagram: AstroDiagram? = nil
    var note: String? = nil
    var plainValue: String? = nil   // a magnitude or a distance in parsecs, shown as it is
    var figures = 3

    var copyValue: Double? = nil    // what is copied, where it is not the value in SI units: a distance in parsecs
    var converts = true             // a step converting the answer to the unit easier to picture, where its own steps do not

    var shownValue: String { plainValue ?? Format.number(value, figures: figures) + (unit.isEmpty ? "" : " " + unit) }

    // A value to as many figures as it is shown with, for copying and for ans.
    static func rounded(_ x: Double, figures: Int = 3) -> Double {
        guard x.isFinite, x != 0 else { return x }
        let step = pow(10, floor(log10(abs(x))) - Double(figures - 1))
        return (x / step).rounded() * step
    }

    var answer: Astronomy {
        let line = "\(symbol) = \(shownValue)"
        var steps: [Step] = []
        if !given.isEmpty {
            steps.append(Step(label: given.count == 1 ? "Taking the value given" : "Taking the values given",
                              math: t(given.map(\.line).joined(separator: ",  ")), note: sources))
        }
        steps += extra
        if let formula { steps.append(Step(label: "Stating the formula", math: formula)) }
        if let substituted { steps.append(Step(label: "Substituting the values", math: substituted)) }
        let alternative = plainValue == nil ? Format.alternative(value, dimension) : nil
        if let (v, u) = alternative, converts {
            steps.append(Step(label: "Converting to \(Worked.unitWords[u] ?? u)", math: t("\(symbol) ≈ \(Format.number(v)) \(u)")))
        }
        steps += after
        var d = Details(name: symbol, equation: t(title), steps: steps, solutions: [t(line)], note: note, f: { _ in .nan }, roots: [])
        d.graph = graph
        d.diagram = diagram
        let approx = alternative.map { "≈ \(Format.number($0.0)) \($0.1) · \(title)" } ?? title
        let copied = copyValue ?? Worked.rounded(value, figures: figures)
        return Astronomy(solution: Solution(exact: line, approx: approx), details: d, copy: String(format: "%.12g", copied), value: copied)
    }

    static let unitWords = ["km": "kilometres", "AU": "astronomical units", "ly": "light years", "nm": "nanometres", "μm": "micrometres",
                            "mm": "millimetres", "minutes": "minutes", "hours": "hours", "days": "days", "years": "years",
                            "km s⁻¹": "kilometres per second", "L☉": "solar luminosities", "M☉": "solar masses", "M⊕": "Earth masses"]

    // MARK: Constants

    static var G: (value: Double, text: String) { let c = Constants.chosen("G") ?? (6.67e-11, "6.67×10⁻¹¹"); return (c.value, String(c.text.split(separator: " ")[0])) }
    static var c: (value: Double, text: String) { let k = Constants.chosen("c") ?? (3.00e8, "3.00×10⁸"); return (k.value, String(k.text.split(separator: " ")[0])) }
    static let sigma = 5.67e-8, wien = 2.90e-3

    static func n(_ x: Double) -> String { Format.number(x) }

    // MARK: Taking the values

    // The value of an argument as the parameter takes it, with where it came from.
    static func given(_ argument: Argument, _ kind: String, _ symbol: String, _ unit: String, word: String) -> Datum {
        switch argument {
        case .body(let body):
            return Datum(symbol: symbol, value: Kind.of(kind).fromBody(body) ?? .nan, unit: unit, from: "\(body.possessive) \(word)")
        case .value(let v, let written):
            var datum = Datum(symbol: symbol, value: v, unit: unit, from: written)
            // Typed in the unit the formula takes: written in as it was typed, 5778 and not 5780.
            let number = unit.isEmpty ? written : written.hasSuffix(" " + unit) ? String(written.dropLast(unit.count + 1)) : nil
            if let number, !number.contains(" ") { datum.written = number }
            return datum
        }
    }

    static func sources(_ givens: [Datum]) -> String? {
        let said = givens.compactMap { g -> String? in
            guard let from = g.from, !(from.first?.isNumber ?? true), from.first != "−" else { return nil }
            return "\(g.symbol) is \(from)"
        }
        return said.isEmpty ? nil : said.joined(separator: "; ") + "."
    }

    // What a function was asked of, for its title: Escape velocity of the Earth; Schwarzschild
    // radius for M = 10 M☉.
    static func title(_ what: String, _ arguments: [Argument], _ data: [Datum]) -> String {
        if let b = arguments.first?.body, arguments.count == 1 { return "\(what) of \(b.name)" }
        return "\(what) for " + zip(arguments, data).map { a, d in "\(d.symbol) = \(a.body?.name ?? d.from ?? d.shown)" }.joined(separator: ", ")
    }

    static func power(_ base: String, _ k: String) -> Math { .power(t(base), t(k)) }
    static func bracketed(_ s: String) -> Math { s.contains("×") || s.hasPrefix("−") ? .group(t(s)) : t(s) }

    // MARK: Each function

    // A mass looked up, or a mass typed in another unit, in kilograms and set beside the Earth's
    // and the Sun's.
    static func mass(_ form: Int, _ a: [Argument]) throws -> Worked {
        let M = given(a[0], "mass", "M", "kg", word: "mass")
        var w = Worked(title: a[0].body.map { "Mass of \($0.name)" } ?? "\(M.from ?? M.shown) in kilograms", symbol: "M", value: M.value, unit: "kg", dimension: .mass, given: [M],
                       sources: sources([M]), formula: nil, substituted: nil)
        let earth = M.value / 5.97e24, sun = M.value / Body.solarMass
        w.converts = false
        w.after = [Step(label: "Comparing it with the Earth and the Sun", math: t("M = \(n(earth)) M⊕ = \(n(sun)) M☉"),
                        note: "M⊕ = 5.97×10²⁴ kg and M☉ = 1.99×10³⁰ kg, as the IB data booklet gives them.")]
        if let body = a[0].body, let R = body.radius, let rho = body.density {
            w.after.append(Step(label: "Finding the mean density", math: row(t("ρ = "), .fraction(t("M"), row(t("⁴⁄₃π"), power("R", "3"))), t(" = \(n(rho)) kg m⁻³")),
                                note: "With \(body.possessive) mean radius, R = \(n(R)) m."))
        }
        return w
    }

    static func schwarzschild(_ form: Int, _ a: [Argument]) throws -> Worked {
        let M = given(a[0], "mass", "M", "kg", word: "mass")
        let r = 2 * G.value * M.value / (c.value * c.value)
        var w = Worked(title: title("Schwarzschild radius", a, [M]), symbol: "r_s", value: r, unit: "m", dimension: .length, given: [M],
                       sources: sources([M]), formula: row(t("r_s = "), .fraction(t("2GM"), power("c", "2"))),
                       substituted: row(t("r_s = "), .fraction(t("2 × \(G.text) × \(M.bare)"), .power(bracketed(c.text), t("2")))))
        if let body = a[0].body, let R = body.radius {
            w.after.append(Step(label: "Comparing it with the radius", math: nil,
                                note: "\(body.title) has a radius of \(n(R)) m, \(n(R / r)) times its Schwarzschild radius; it would have to be squeezed inside r_s to become a black hole."))
        }
        w.diagram = .blackHole(BlackHolePicture(name: a[0].body?.name ?? M.from ?? M.shown, rs: r, radius: a[0].body?.radius))
        return w
    }

    static func escape(_ form: Int, _ a: [Argument]) throws -> Worked {
        let (M, R) = form == 0 ? (given(a[0], "mass", "M", "kg", word: "mass"), given(a[0], "radius", "r", "m", word: "radius"))
                               : (given(a[0], "mass", "M", "kg", word: "mass"), given(a[1], "radius", "r", "m", word: "radius"))
        let v = (2 * G.value * M.value / R.value).squareRoot()
        var w = Worked(title: title("Escape velocity", a, [M, R]), symbol: "v_esc", value: v, unit: "m s⁻¹", dimension: .speed, given: [M, R],
                       sources: sources([M, R]), formula: row(t("v_esc = "), .root(.fraction(t("2GM"), t("r")))),
                       substituted: row(t("v_esc = "), .root(.fraction(t("2 × \(G.text) × \(M.bare)"), t(R.bare)))))
        if v > c.value {
            w.note = "This is faster than light: nothing escapes, and r is inside the Schwarzschild radius, where this formula no longer holds."
        }
        let unit = Plotting.length(R.value)
        let k = (2 * G.value * M.value).squareRoot() / 1e3
        w.graph = Plotting.graph(x: unit.name, y: "km s⁻¹", label: "v_esc in km s⁻¹ against r in \(unit.name)",
                                 f: { x in x > 0 ? k / (x * unit.factor).squareRoot() : .nan },
                                 point: (R.value / unit.factor, v / 1e3), xMax: 4 * R.value / unit.factor, yMax: 2.2 * v / 1e3)
        return w
    }

    static func gravity(_ form: Int, _ a: [Argument]) throws -> Worked {
        let M = given(a[0], "mass", "M", "kg", word: "mass")
        let R = given(a[form == 0 ? 0 : 1], "radius", "R", "m", word: "radius")
        let g = G.value * M.value / (R.value * R.value)
        var w = Worked(title: title("Surface gravity", a, [M, R]), symbol: "g", value: g, unit: "m s⁻²", dimension: .none, given: [M, R],
                       sources: sources([M, R]), formula: row(t("g = "), .fraction(t("GM"), power("R", "2"))),
                       substituted: row(t("g = "), .fraction(t("\(G.text) × \(M.bare)"), .power(bracketed(R.bare), t("2")))))
        if let earth = Body.named("earth"), a[0].body?.id != "earth" {
            let gE = G.value * earth.mass / (earth.radius! * earth.radius!)
            w.after.append(Step(label: "Comparing it with the Earth", math: t("g/g⊕ = \(n(g / gE))"),
                                note: "The Earth’s own is \(n(gE)) m s⁻² from the same data."))
        }
        let unit = Plotting.length(R.value)
        let gm = G.value * M.value
        w.graph = Plotting.graph(x: unit.name, y: "m s⁻²", label: "g in m s⁻² against r in \(unit.name)",
                                 f: { x in x > 0 ? gm / pow(x * unit.factor, 2) : .nan },
                                 point: (R.value / unit.factor, g), xMax: 4 * R.value / unit.factor, yMax: 2.5 * g)
        return w
    }

    // The orbit, and what it is round: from one body, its own orbit round its primary.
    static func orbit(_ form: Int, _ a: [Argument]) throws -> (Datum, Datum, String) {
        if form == 0 {
            guard let body = a[0].body, let o = body.orbit, let primary = body.primary else { throw Problem(message: "Not in orbit", detail: "Give a and M") }
            return (Datum(symbol: "a", value: o.a, unit: "m", from: "the radius of \(body.possessive) orbit"),
                    Datum(symbol: "M", value: primary.mass, unit: "kg", from: "\(primary.possessive) mass"), "\(body.name) round \(primary.name)")
        }
        let a0 = given(a[0], "orbit", "a", "m", word: "orbital radius"), M = given(a[1], "central", "M", "kg", word: "mass")
        return (a0, M, "an orbit of radius \(a0.from ?? a0.shown) round \(a[1].body?.name ?? M.from ?? M.shown)")
    }

    // The orbit drawn round what it circles, with the orbits of its neighbours there for scale.
    static func picture(_ form: Int, _ a: [Argument], _ r: Datum, _ M: Datum, hill: Double? = nil) -> AstroDiagram {
        let satellite = form == 0 ? a[0].body : nil
        let primary = satellite?.primary ?? a.last?.body
        let neighbours = primary.map { p in
            Body.all.filter { $0.orbit?.around == p.id && $0.id != satellite?.id && $0.orbit!.a > r.value / 4.5 && $0.orbit!.a < r.value * 4.5 }
                .map { OrbitPicture.Ring(name: $0.title, a: $0.orbit!.a) }
        } ?? []
        let gm = G.value * M.value
        return .orbit(OrbitPicture(primary: primary?.title ?? "M", primaryIsStar: primary.map { $0.kind == "star" } ?? true,
                                   satellite: satellite?.title ?? "", a: r.value, speed: (gm / r.value).squareRoot(),
                                   period: 2 * Double.pi * (pow(r.value, 3) / gm).squareRoot(), others: neighbours, hill: hill))
    }

    // A star on the H–R diagram, among those of the table: one given by name, or one worked out.
    static func hr(_ a: [Argument], temperature: Double? = nil, luminosity: Double? = nil) -> AstroDiagram? {
        let named = a.count == 1 ? a[0].body : nil
        guard named.map({ $0.temperature != nil && $0.luminosity != nil }) ?? (temperature != nil && luminosity != nil) else { return nil }
        var stars = Body.all.compactMap { b -> HRPicture.Star? in
            guard let T = b.temperature, let L = b.luminosity else { return nil }
            return HRPicture.Star(name: b.title, temperature: T, luminosity: L / Body.solarLuminosity, marked: b.id == named?.id)
        }
        if named == nil, let T = temperature, let L = luminosity {
            stars.append(HRPicture.Star(name: "This star", temperature: T, luminosity: L / Body.solarLuminosity, marked: true))
        }
        return .hr(HRPicture(stars: stars))
    }

    static func period(_ form: Int, _ a: [Argument]) throws -> Worked {
        let (r, M, what) = try orbit(form, a)
        let T = 2 * Double.pi * (pow(r.value, 3) / (G.value * M.value)).squareRoot()
        var w = Worked(title: "Orbital period of \(what)", symbol: "T", value: T, unit: "s", dimension: .time, given: [r, M],
                       sources: sources([r, M]), formula: row(t("T = 2π"), .root(.fraction(power("a", "3"), t("GM")))),
                       substituted: row(t("T = 2π"), .root(.fraction(.power(bracketed(r.bare), t("3")),
                                                                     t("\(G.text) × \(M.bare)")))))
        w.extra = [Step(label: "Applying Kepler’s third law", math: row(power("T", "2"), t(" = "), .fraction(row(t("4π²"), power("a", "3")), t("GM"))),
                        note: "For a circular orbit, gravity provides the centripetal force: GMm/a² = m(2π/T)²a, so T² = 4π²a³/GM.")]
        let x = Plotting.length(r.value), y = Plotting.time(T)
        let k = 2 * Double.pi / (G.value * M.value).squareRoot()
        w.graph = Plotting.graph(x: x.name, y: y.name, label: "T in \(y.name) against a in \(x.name)",
                                 f: { v in v >= 0 ? k * pow(v * x.factor, 1.5) / y.factor : .nan },
                                 point: (r.value / x.factor, T / y.factor), xMax: 2.2 * r.value / x.factor, yMax: 3.6 * T / y.factor)
        w.diagram = picture(form, a, r, M)
        return w
    }

    static func speed(_ form: Int, _ a: [Argument]) throws -> Worked {
        let (r, M, what) = try orbit(form, a)
        let v = (G.value * M.value / r.value).squareRoot()
        var w = Worked(title: "Orbital speed of \(what)", symbol: "v", value: v, unit: "m s⁻¹", dimension: .speed, given: [r, M],
                       sources: sources([r, M]), formula: row(t("v = "), .root(.fraction(t("GM"), t("a")))),
                       substituted: row(t("v = "), .root(.fraction(t("\(G.text) × \(M.bare)"), t(r.bare)))))
        let x = Plotting.length(r.value)
        let gm = G.value * M.value
        w.graph = Plotting.graph(x: x.name, y: "km s⁻¹", label: "v in km s⁻¹ against a in \(x.name)",
                                 f: { u in u > 0 ? (gm / (u * x.factor)).squareRoot() / 1e3 : .nan },
                                 point: (r.value / x.factor, v / 1e3), xMax: 3 * r.value / x.factor, yMax: 2.4 * v / 1e3)
        w.diagram = picture(form, a, r, M)
        return w
    }

    static func hill(_ form: Int, _ a: [Argument]) throws -> Worked {
        let r: Datum, m: Datum, M: Datum, what: String
        if form == 0 {
            guard let body = a[0].body, let o = body.orbit, let primary = body.primary else { throw Problem(message: "Not in orbit", detail: "Give a, m and M") }
            r = Datum(symbol: "a", value: o.a, unit: "m", from: "the radius of \(body.possessive) orbit")
            m = Datum(symbol: "m", value: body.mass, unit: "kg", from: "\(body.possessive) mass")
            M = Datum(symbol: "M", value: primary.mass, unit: "kg", from: "\(primary.possessive) mass")
            what = body.name
        } else {
            r = given(a[0], "orbit", "a", "m", word: "orbital radius")
            m = given(a[1], "mass", "m", "kg", word: "mass")
            M = given(a[2], "central", "M", "kg", word: "mass")
            what = "a body of mass \(m.from ?? m.shown)"
        }
        guard m.value < M.value else { throw Problem(message: "The satellite is the heavier", detail: "m must be much less than M") }
        let rH = r.value * pow(m.value / (3 * M.value), 1.0 / 3)
        var w = Worked(title: "Hill radius of \(what)", symbol: "r_H", value: rH, unit: "m", dimension: .length, given: [r, m, M],
                       sources: sources([r, m, M]), formula: row(t("r_H ≈ a"), .radical(.fraction(t("m"), t("3M")), index: t("3"))),
                       substituted: row(t("r_H ≈ \(r.bare) × "),
                                        .radical(.fraction(t(m.bare), t("3 × \(M.bare)")), index: t("3"))))
        w.note = "Within this distance the body’s own gravity holds a moon against the pull of what it orbits."
        w.diagram = picture(form, form == 0 ? a : [a[0], a[2]], r, M, hill: rH)
        return w
    }

    static func roche(_ form: Int, _ a: [Argument]) throws -> Worked {
        let primary: Body, satellite: Body
        if form == 0 {
            guard let s = a[0].body, let p = s.primary else { throw Problem(message: "Not in orbit", detail: "Give the primary and the satellite") }
            (primary, satellite) = (p, s)
        } else {
            guard let p = a[0].body, let s = a[1].body else { throw Problem(message: "Two bodies are wanted", detail: "roche_limit(earth, moon)") }
            (primary, satellite) = (p, s)
        }
        guard let R = primary.radius, let rhoM = primary.density, let rhoS = satellite.density else {
            throw Problem(message: "No radius for \(primary.name)", detail: "The Roche limit needs both densities")
        }
        let d = R * pow(2 * rhoM / rhoS, 1.0 / 3)
        let RG = Datum(symbol: "R", value: R, unit: "m", from: "\(primary.possessive) radius")
        var w = Worked(title: "Roche limit of \(satellite.name) round \(primary.name)", symbol: "d", value: d, unit: "m", dimension: .length,
                       given: [RG], sources: sources([RG]),
                       formula: row(t("d = R"), .radical(.fraction(t("2ρ_M"), t("ρ_m")), index: t("3"))),
                       substituted: row(t("d = \(n(R)) × "), .radical(.fraction(t("2 × \(n(rhoM))"), t(n(rhoS))), index: t("3"))))
        w.extra = [Step(label: "Finding the densities", math: t("ρ_M = \(n(rhoM)) kg m⁻³,  ρ_m = \(n(rhoS)) kg m⁻³"),
                        note: "Each is the mass over the volume of a sphere, ρ = M/(4/3 πR³), for \(primary.name) and \(satellite.name).")]
        if let o = satellite.orbit, o.around == primary.id {
            w.after.append(Step(label: "Comparing it with the orbit", math: t("a/d = \(n(o.a / d))"),
                                note: "\(satellite.title) orbits at \(n(o.a)) m, well outside the limit."))
        }
        w.note = "For a rigid satellite. A fluid one is pulled apart further out, at about 2.44 R ∛(ρ_M/ρ_m)."
        return w
    }

    static func luminosity(_ form: Int, _ a: [Argument]) throws -> Worked {
        let R = given(a[0], "radius", "R", "m", word: "radius")
        let T = given(a[form == 0 ? 0 : 1], "temperature", "T", "K", word: "surface temperature")
        let L = sigma * 4 * Double.pi * R.value * R.value * pow(T.value, 4)
        var w = Worked(title: title("Luminosity", a, [R, T]), symbol: "L", value: L, unit: "W", dimension: .power, given: [R, T],
                       sources: sources([R, T]), formula: row(t("L = σ4π"), power("R", "2"), power("T", "4")),
                       substituted: row(t("L = 5.67×10⁻⁸ × 4π × "), .power(bracketed(R.bare), t("2")), t(" × "),
                                        .power(t(T.bare), t("4"))))
        w.note = "σ = 5.67×10⁻⁸ W m⁻² K⁻⁴, the Stefan–Boltzmann constant; the star is taken as a black body."
        w.diagram = hr(form == 0 ? a : [], temperature: T.value, luminosity: L)
        return w
    }

    static func wien(_ form: Int, _ a: [Argument]) throws -> Worked {
        let T = given(a[0], "temperature", "T", "K", word: "surface temperature")
        guard T.value > 0 else { throw Problem(message: "A temperature above absolute zero is wanted", detail: "T in kelvin") }
        let lambda = wien / T.value
        var w = Worked(title: title("Peak wavelength", a, [T]), symbol: "λ_max", value: lambda, unit: "m", dimension: .length, given: [T],
                       sources: sources([T]), formula: row(t("λ_max = "), .fraction(t("b"), t("T"))),
                       substituted: row(t("λ_max = "), .fraction(t("2.90×10⁻³"), t(T.bare))))
        let nm = lambda / 1e-9
        let band = nm < 10 ? "X-rays" : nm < 400 ? "ultraviolet" : nm < 450 ? "violet light" : nm < 495 ? "blue light" : nm < 570 ? "green light"
            : nm < 590 ? "yellow light" : nm < 750 ? "red light" : nm < 1e6 ? "infrared" : "microwaves"
        w.after = [Step(label: "Placing it in the spectrum", math: nil, note: "At \(n(nm)) nm the peak lies in the \(band).")]
        w.note = "b = 2.90×10⁻³ m K, Wien’s constant; the body is taken as a black body."
        // The black-body spectrum, its height at the peak taken as 1.
        let hcOverK = 1.4388e-2
        func planck(_ x: Double) -> Double { let l = x * 1e-9; return 1 / (pow(l, 5) * (exp(hcOverK / (l * T.value)) - 1)) }
        let peak = planck(nm)
        w.graph = Plotting.graph(x: "nm", y: "relative intensity", label: "Black-body spectrum at \(T.shown), peak = 1",
                                 f: { x in x > 0 ? planck(x) / peak : .nan }, point: (nm, 1), xMax: 5 * nm, yMax: 1.2)
        w.diagram = hr(a)
        return w
    }

    static func parallax(_ form: Int, _ a: [Argument]) throws -> Worked {
        let p = given(a[0], "parallax", "p", "rad", word: "parallax")
        let arcsec = p.value / AstroUnit.arcsecond
        guard arcsec > 0 else { throw Problem(message: "A parallax greater than zero is wanted", detail: "p in arcseconds") }
        let d = 1 / arcsec
        let P = Datum(symbol: "p", value: arcsec, unit: "arcsec", from: a[0].body.map { "\($0.possessive) parallax" } ?? writtenOf(a[0]))
        var w = Worked(title: a[0].body.map { "Distance of \($0.name) from its parallax" } ?? "Distance for p = \(P.from ?? P.shown)", symbol: "d", value: d * Body.parsec, unit: "m", dimension: .length,
                       given: [P], sources: sources([P]), formula: row(t("d (pc) = "), .fraction(t("1"), t("p (arcsec)"))),
                       substituted: row(t("d = "), .fraction(t("1"), t(n(arcsec))), t(" = \(n(d)) pc")))
        w.plainValue = "\(n(d)) pc"
        w.copyValue = Worked.rounded(d)
        w.after = [Step(label: "Converting to light years and metres", math: t("d = \(n(d * Body.parsec / Body.lightYear)) ly = \(n(d * Body.parsec)) m"),
                        note: "1 pc = 3.26 ly = 3.09×10¹⁶ m.")]
        return w
    }

    static func writtenOf(_ a: Argument) -> String? { if case .value(_, let w) = a { w } else { nil } }

    static func absolute(_ form: Int, _ a: [Argument]) throws -> Worked {
        let m: Datum, d: Datum
        if form == 0, let body = a[0].body {
            m = Datum(symbol: "m", value: body.apparent ?? .nan, unit: "", from: "\(body.possessive) apparent magnitude")
            d = Datum(symbol: "d", value: (body.distanceFromEarth ?? .nan) / Body.parsec, unit: "pc", from: "\(body.possessive) distance")
        } else {
            m = given(a[0], "apparent", "m", "", word: "apparent magnitude")
            let dd = given(a[1], "distance", "d", "pc", word: "distance")
            d = Datum(symbol: "d", value: dd.value / Body.parsec, unit: "pc", from: dd.from)
        }
        guard d.value > 0 else { throw Problem(message: "A distance greater than zero is wanted", detail: "d") }
        let M = m.value - 5 * log10(d.value / 10)
        var w = Worked(title: title("Absolute magnitude", a, [m, d]), symbol: "M", value: M, unit: "", dimension: .none,
                       given: [m.magnitude, d], sources: sources([m, d]),
                       formula: row(t("M = m − 5 log₁₀"), .group(.fraction(t("d"), t("10 pc")))),
                       substituted: row(t("M = \(Format.magnitude(m.value)) − 5 log₁₀"), .group(.fraction(t(n(d.value)), t("10")))))
        w.plainValue = Format.magnitude(M)
        w.copyValue = (M * 100).rounded() / 100
        w.note = "The magnitude the star would have if it were seen from a distance of 10 pc; the smaller the number, the brighter the star."
        w.diagram = form == 0 ? hr(a) : nil
        return w
    }

    static func apparent(_ form: Int, _ a: [Argument]) throws -> Worked {
        let M = given(a[0], "absolute", "M", "", word: "absolute magnitude")
        let dd = given(a[1], "distance", "d", "pc", word: "distance")
        let d = Datum(symbol: "d", value: dd.value / Body.parsec, unit: "pc", from: dd.from)
        guard d.value > 0 else { throw Problem(message: "A distance greater than zero is wanted", detail: "d") }
        let m = M.value + 5 * log10(d.value / 10)
        var w = Worked(title: "Apparent magnitude at \(d.from ?? d.shown)", symbol: "m", value: m, unit: "", dimension: .none, given: [M.magnitude, d],
                       sources: sources([M, d]), formula: row(t("m = M + 5 log₁₀"), .group(.fraction(t("d"), t("10 pc")))),
                       substituted: row(t("m = \(Format.magnitude(M.value)) + 5 log₁₀"), .group(.fraction(t(n(d.value)), t("10")))))
        w.plainValue = Format.magnitude(m)
        w.copyValue = (m * 100).rounded() / 100
        return w
    }

    static func brightness(_ form: Int, _ a: [Argument]) throws -> Worked {
        let L = given(a[0], "luminosity", "L", "W", word: "luminosity")
        let d = given(a[form == 0 ? 0 : 1], "distance", "d", "m", word: "distance from the Earth")
        let b = L.value / (4 * Double.pi * d.value * d.value)
        var w = Worked(title: title("Apparent brightness", a, [L, d]), symbol: "b", value: b, unit: "W m⁻²", dimension: .none, given: [L, d],
                       sources: sources([L, d]), formula: row(t("b = "), .fraction(t("L"), row(t("4π"), power("d", "2")))),
                       substituted: row(t("b = "), .fraction(t(L.bare), row(t("4π × "), .power(bracketed(d.bare), t("2"))))))
        if a[0].body?.id == "sun" { w.note = "This is the solar constant, the power arriving on each square metre above the atmosphere." }
        w.diagram = form == 0 ? hr(a) : nil
        return w
    }

    static func redshift(_ form: Int, _ a: [Argument]) throws -> Worked {
        var given: [Datum] = [], extra: [Step] = []
        let z: Double
        if form == 0 {
            guard case .value(let v, let w) = a[0] else { throw Problem(message: "A redshift is a number", detail: "z") }
            z = v
            given = [Datum(symbol: "z", value: v, unit: "", from: w, written: w)]
        } else {
            guard case .value(let l, let lw) = a[0], case .value(let l0, let l0w) = a[1], l0 > 0 else { throw Problem(message: "Two wavelengths are wanted", detail: "observed, then at rest") }
            z = (l - l0) / l0
            given = [Datum(symbol: "λ", value: l, unit: "m", from: lw), Datum(symbol: "λ₀", value: l0, unit: "m", from: l0w)]
            extra = [Step(label: "Finding the redshift", math: row(t("z = "), .fraction(t("Δλ"), t("λ₀")), t(" = "),
                                                                    .fraction(t("\(n(l)) − \(n(l0))"), t(n(l0))), t(" = \(Format.number(z))")))]
        }
        let v = c.value * z
        var w = Worked(title: z < 0 ? "Approach speed for a blueshift of \(Format.number(-z))" : "Recession speed for z = \(form == 0 ? given[0].bare : Format.number(z))",
                       symbol: "v", value: v, unit: "m s⁻¹", dimension: .speed, given: given, sources: nil,
                       formula: row(t("v ≈ cz")), substituted: row(t("v ≈ \(c.text) × \(Format.number(z))")))
        w.extra = extra
        if abs(z) > 0.1 {
            w.note = "z = v/c holds only for speeds much less than that of light; at z = \(Format.number(z)) it is no longer a good approximation."
        } else if z < 0 {
            w.note = "A negative z is a blueshift: the source is coming nearer."
        }
        var lines = SpectrumPicture.hydrogen
        var marked: Int?
        if form == 1, case .value(let l0, _) = a[1] {
            // The line given, among the usual ones where it is one of them, and otherwise added.
            let nm = l0 / 1e-9
            if let i = lines.firstIndex(where: { abs($0.rest - nm) < 2 }) { marked = i } else {
                lines.append(SpectrumPicture.Line(name: "λ₀", rest: nm))
                marked = lines.count - 1
            }
        }
        w.diagram = .spectrum(SpectrumPicture(z: z, lines: lines, marked: marked))
        return w
    }
}

// MARK: - Diagrams

// A picture of the answer that is no curve: what is drawn is decided here, how in AstronomyDiagram.swift.
enum AstroDiagram {
    case orbit(OrbitPicture)
    case hr(HRPicture)
    case blackHole(BlackHolePicture)
    case spectrum(SpectrumPicture)
    case scientific(AstronomyPicture)

    var title: String {
        switch self {
        case .orbit: return "Orbit"
        case .hr: return "Hertzsprung–Russell diagram"
        case .blackHole: return "Black hole, to scale"
        case .spectrum: return "Spectrum"
        case .scientific(let picture): return picture.title
        }
    }
}

// A circular orbit seen from above: what is circled, the body on the orbit with its speed, and the
// orbits of neighbours of about the same size, to scale; the Hill sphere, where it was asked for.
struct OrbitPicture {
    struct Ring { var name: String; var a: Double }
    var primary: String
    var primaryIsStar: Bool
    var satellite: String
    var a: Double
    var speed: Double
    var period: Double
    var others: [Ring]
    var hill: Double? = nil
}

// Stars by surface temperature, hotter to the left, and luminosity in solar luminosities, on
// logarithmic scales; one marked.
struct HRPicture {
    struct Star { var name: String; var temperature: Double; var luminosity: Double; var marked: Bool }
    var stars: [Star]
}

// The event horizon, the photon sphere at 1.5 r_s and the innermost stable circular orbit at 3 r_s.
struct BlackHolePicture {
    var name: String
    var rs: Double
    var radius: Double?   // the body's own radius, for the comparison under it
}

// Absorption lines at rest and as seen, each moved by the factor 1 + z.
struct SpectrumPicture {
    struct Line { var name: String; var rest: Double }   // in nm
    var z: Double
    var lines: [Line]
    var marked: Int? = nil   // the line whose wavelengths were given

    static let hydrogen = [Line(name: "Hδ", rest: 410.2), Line(name: "Hγ", rest: 434.0), Line(name: "Hβ", rest: 486.1),
                           Line(name: "Na D", rest: 589.3), Line(name: "Hα", rest: 656.3)]
}

// MARK: - Graphs

enum Plotting {
    // A unit for an axis that keeps its numbers between about 1 and 1000.
    static func length(_ x: Double) -> (name: String, factor: Double) {
        if x >= 0.05 * Body.au { return ("AU", Body.au) }
        if x >= 1e9 { return ("million km", 1e9) }
        if x >= 1e6 { return ("thousand km", 1e6) }
        return ("km", 1e3)
    }

    static func time(_ x: Double) -> (name: String, factor: Double) {
        if x >= 2 * 3.156e7 { return ("years", 3.156e7) }
        if x >= 2 * 86_400 { return ("days", 86_400) }
        if x >= 7_200 { return ("hours", 3_600) }
        return ("minutes", 60)
    }

    // One curve, the point worked out marked on it (to the three figures of the answer, which its
    // label gives), in a window from the origin that shows both.
    static func graph(x: String, y: String, label: String, f: @escaping (Double) -> Double, point: (Double, Double), xMax: Double, yMax: Double) -> Graph {
        var g = Graph(xName: x, yName: y, curves: [Graph.Curve(shape: .function(f), label: t(label))], points: [CGPoint(x: Worked.rounded(point.0), y: Worked.rounded(point.1))])
        g.frame = (0...xMax, 0...yMax)
        return g
    }
}
