import Foundation

// How Astronomy's names and values are written, on the card and in the panel, so that they read as the
// rest of the app does: a call as it reads, bodies by their names, headings in sentence case with the
// hyphens English gives them, notes as sentences, numbers as they are printed.
enum AstronomyWorkingText {
    // A name as a heading is written: best_period, Best period; semi_major_axis, Semi-major axis.
    static func name(_ name: String) -> String {
        switch name {
        case "body1": return "First body"
        case "body2": return "Second body"
        case "at": return "Epoch"
        case "rms": return "RMS"
        case "isp": return "Specific impulse"
        case "k_B", "c", "G", "h", "σ": return name
        default:
            let words = hyphenated(name.replacingOccurrences(of: "_", with: " "))
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    private static func hyphenated(_ s: String) -> String {
        s.replacingOccurrences(of: "semi major", with: "semi-major", options: .caseInsensitive)
            .replacingOccurrences(of: "Semi major", with: "Semi-major")
    }

    // A body as it is named on its own, earth as Earth and sgr_a as Sgr A*; nil for what is no body.
    static func body(_ id: String) -> String? {
        guard let body = Body.named(id), body.id == id.lowercased() else { return nil }
        let name = body.name.hasPrefix("the ") ? String(body.name.dropFirst(4)) : body.name
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // A label from the engine: Mass of earth as Mass of the Earth, Semi major axis as Semi-major axis.
    static func label(_ label: String) -> String {
        var out = hyphenated(label)
        if let range = out.range(of: " of "), let body = Body.named(String(out[range.upperBound...])) {
            out = String(out[..<range.upperBound]) + body.name
        }
        return out
    }

    // A note as a sentence: capital first, full stop last.
    static func sentence(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let capital = first.uppercased() + trimmed.dropFirst()
        return ".!?".contains(capital.last!) ? capital : capital + "."
    }

    // What was typed after @, as it is understood, to be set as the rest of the app sets what was typed:
    // escape_velocity(earth) as Escape velocity (Earth), schwarzschild_radius(10 M_sun) as Schwarzschild
    // radius (10 M☉). What is not a call is left as typed.
    static func call(_ typed: String) -> Math {
        let text = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^@\\s*", with: "", options: .regularExpression)
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")"),
              text[..<open].allSatisfy({ $0.isLetter || $0 == "_" }), open != text.startIndex else { return .text(text) }
        let title = name(String(text[..<open]))
        let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        let arguments = Astronomy.topLevel(inside).map { argument($0.trimmingCharacters(in: .whitespaces)) }
        return .row([.text(title + " "), .group(.text(arguments.joined(separator: ", ")))])
    }

    // One argument as it reads: a body by its name, units in their signs, numbers as printed.
    private static func argument(_ a: String) -> String {
        if let body = body(a) { return body }
        if let eq = a.firstIndex(of: "="), !a.hasPrefix("{"), a[..<eq].allSatisfy({ $0.isLetter || $0 == "_" }) {
            return name(String(a[..<eq])).lowercased() + " = " + argument(String(a[a.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
        }
        var out = shown(a)
        for (written, sign) in [("M_sun", "M☉"), ("Msun", "M☉"), ("M_earth", "M⊕"), ("R_sun", "R☉"), ("R_earth", "R⊕"), ("L_sun", "L☉"),
                                ("M_jup", "M_J"), ("m/s2", "m/s²"), ("kg/m3", "kg/m³"), ("m2/kg", "m²/kg"), ("cm2/g", "cm²/g")] {
            out = out.replacingOccurrences(of: written, with: sign)
        }
        return out.replacingOccurrences(of: ",", with: ", ").replacingOccurrences(of: ",  ", with: ", ")
    }

    // The card's line of several values, each named as a heading is and written as it is read:
    // best_period: 7.6e+04 s; power: … is Best period: 7.6 × 10⁴ s; Power: ….
    static func line(_ text: String) -> String {
        let named = try! NSRegularExpression(pattern: "(^|; )([a-z][A-Za-z0-9_]*): ")
        let source = text as NSString
        var out = "", last = 0
        for match in named.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: last, length: match.range.location - last))
            out += source.substring(with: match.range(at: 1)) + name(source.substring(with: match.range(at: 2))) + ": "
            last = match.range.location + match.range.length
        }
        return shown(out + source.substring(from: last))
    }

    // A value as it is read, not as a program writes it: 5.9722e+24 kg is 5.9722 × 10²⁴ kg, and
    // m / s is m/s. What is copied is still the engine's own.
    static func shown(_ value: String) -> String {
        if let body = body(value.trimmingCharacters(in: .whitespaces)) { return body }
        let superscripts: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷",
                                                     "8": "⁸", "9": "⁹", "-": "⁻"]
        let pattern = try! NSRegularExpression(pattern: "(?<![A-Za-z_0-9.])([0-9]+(?:\\.[0-9]+)?)[eE]([+-]?)0*([0-9]+)")
        let text = value as NSString
        var out = "", last = 0
        for match in pattern.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            out += text.substring(with: NSRange(location: last, length: match.range.location - last))
            let exponent = (text.substring(with: match.range(at: 2)) == "-" ? "-" : "") + text.substring(with: match.range(at: 3))
            out += text.substring(with: match.range(at: 1)) + " × 10" + String(exponent.map { superscripts[$0] ?? $0 })
            last = match.range.location + match.range.length
        }
        out += text.substring(from: last)
        return out.replacingOccurrences(of: " / ", with: "/")
    }
}
