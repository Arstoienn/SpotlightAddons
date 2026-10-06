import CryptoKit
import Foundation

// SHA256("hello") and SHA1("hello"), in capitals or not: the digest of the text, which is taken
// as it is typed, with or without quotation marks, and hashed as UTF-8. It is written in
// hexadecimal, which is not a number to do sums with; asked for as decimal or binary,
// sha256("hello", decimal), it is the same digest as a whole number, and can be.
struct Hash {
    enum Algorithm: String {
        case sha256 = "SHA-256", sha1 = "SHA-1"
    }
    enum Format: String {
        case hexadecimal, decimal, binary
    }

    var algorithm: Algorithm
    var message: String
    var format: Format

    var bytes: [UInt8] { Array(message.utf8) }

    var digest: [UInt8] {
        switch algorithm {
        case .sha256: return Array(SHA256.hash(data: Data(bytes)))
        case .sha1: return Array(Insecure.SHA1.hash(data: Data(bytes)))
        }
    }

    // MARK: Reading

    // The whole of what was typed, when that is one call and nothing else.
    static func parse(_ typed: String) -> Hash? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard let call = calls(in: text).first, call.range == text.startIndex..<text.endIndex else { return nil }
        return call.hash
    }

    // What was typed with each digest asked for as a number written in as that number, for the
    // sum it is part of to be worked out; nil if there is one in hexadecimal, which cannot be.
    // The number is as close as sixteen figures come to it.
    static func numbers(in typed: String) -> String? {
        var out = typed
        for call in calls(in: typed).reversed() {
            guard call.hash.format != .hexadecimal else { return nil }
            let value = call.hash.digest.reduce(0.0) { $0 * 256 + Double($1) }
            out.replaceSubrange(call.range, with: String(format: "%.17g", value))
        }
        return out
    }

    // Every sha256(…) and sha1(…) in the text, with where it is. The bracket that closes one is
    // looked for outside quotation marks, so that the text hashed may have brackets in it.
    static func calls(in text: String) -> [(range: Range<String.Index>, hash: Hash)] {
        let names: [(String, Algorithm)] = [("sha-256", .sha256), ("sha256", .sha256), ("sha-1", .sha1), ("sha1", .sha1)]
        let pairs: [Character: Character] = ["\"": "\"", "'": "'", "“": "”", "‘": "’"]
        var found: [(range: Range<String.Index>, hash: Hash)] = []
        var i = text.startIndex
        while i < text.endIndex {
            guard let (name, algorithm) = names.first(where: { text[i...].lowercased().hasPrefix($0.0) }) else {
                i = text.index(after: i)
                continue
            }
            var j = text.index(i, offsetBy: name.count)
            while j < text.endIndex, text[j] == " " { j = text.index(after: j) }
            guard j < text.endIndex, text[j] == "(" else {
                i = text.index(after: i)
                continue
            }
            let inside = text.index(after: j)
            var depth = 1, closing: Character?, k = inside
            while k < text.endIndex {
                let c = text[k]
                if let end = closing {
                    if c == end { closing = nil }
                } else if let end = pairs[c] {
                    closing = end
                } else if c == "(" {
                    depth += 1
                } else if c == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                k = text.index(after: k)
            }
            guard k < text.endIndex else { return found }   // never closed: still being typed
            let (message, format) = argument(String(text[inside..<k]))
            found.append((i..<text.index(after: k), Hash(algorithm: algorithm, message: message, format: format)))
            i = text.index(after: k)
        }
        return found
    }

    // "hello", decimal: the text, out of its quotation marks if it is in them, and how the
    // digest is to be written, which is the last word when that word is one of the three.
    private static func argument(_ inside: String) -> (String, Format) {
        var text = inside.trimmingCharacters(in: .whitespaces)
        var format = Format.hexadecimal
        if let comma = text.lastIndex(of: ",") {
            let word = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces).lowercased()
            let named: [String: Format] = ["decimal": .decimal, "dec": .decimal, "binary": .binary, "bin": .binary,
                                           "hex": .hexadecimal, "hexadecimal": .hexadecimal]
            if let chosen = named[word] {
                format = chosen
                text = text[..<comma].trimmingCharacters(in: .whitespaces)
            }
        }
        for (open, close) in [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")] where text.count >= 2 && text.hasPrefix(open) && text.hasSuffix(close) {
            return (String(text.dropFirst().dropLast()), format)
        }
        return (text, format)
    }

    // MARK: Writing

    var hexadecimal: String { digest.map { String(format: "%02x", $0) }.joined() }

    // The digest as one whole number: long division of its bytes by ten, a digit at a time.
    var decimal: String {
        var number = digest, digits: [Character] = []
        while number.contains(where: { $0 != 0 }) {
            var remainder = 0
            for i in number.indices {
                let value = remainder * 256 + Int(number[i])
                number[i] = UInt8(value / 10)
                remainder = value % 10
            }
            digits.append(Character(String(remainder)))
        }
        return digits.isEmpty ? "0" : String(digits.reversed())
    }

    var binary: String { digest.map { byte in String(repeating: "0", count: 8 - String(byte, radix: 2).count) + String(byte, radix: 2) }.joined() }

    var written: String {
        switch format {
        case .hexadecimal: return hexadecimal
        case .decimal: return decimal
        case .binary: return binary
        }
    }

    private var size: String { bytes.count == 1 ? "1 byte" : "\(bytes.count) bytes" }

    // The card has one line: all of the digest in hexadecimal or decimal, which it shrinks to
    // fit, and the start of it in binary.
    var solution: Solution {
        let shown = format == .binary ? String(binary.prefix(48)) + "…" : written
        return Solution(exact: shown, approx: "\(algorithm.rawValue) digest of \(size), in \(format.rawValue)")
    }

    var details: Details {
        var name = message.count > 40 ? String(message.prefix(40)) + "…" : message
        name = "\(algorithm.rawValue)(\"\(name)\"" + (format == .hexadecimal ? ")" : ", \(format.rawValue))")
        var d = Details(name: "", equation: t(name), steps: [], solutions: [t(written)], note: nil, f: { _ in .nan }, roots: [])
        let listed = bytes.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ") + (bytes.count > 16 ? " …" : "")
        d.steps.append(Step(label: "Encoding the message as UTF-8", math: bytes.isEmpty ? nil : t(listed),
                            note: bytes.isEmpty ? "The message is empty: there are no bytes." : "The message is \(size), written here in hexadecimal."))
        let bits = digest.count * 8
        d.steps.append(Step(label: "Applying \(algorithm.rawValue)", math: nil,
                            note: "The message is padded to a multiple of 512 bits and compressed block by block, which gives a digest of \(bits) bits."))
        switch format {
        case .hexadecimal:
            break
        case .decimal:
            d.steps.append(Step(label: "Reading the digest as a whole number", math: nil,
                                note: "Its \(digest.count * 2) hexadecimal digits are one number in base 16, written here in base 10."))
        case .binary:
            d.steps.append(Step(label: "Writing the digest in binary", math: nil, note: "Each hexadecimal digit is four binary digits."))
            // Eight bytes to a line, to be read; copied, any line gives the whole.
            let groups = digest.map { byte in String(repeating: "0", count: 8 - String(byte, radix: 2).count) + String(byte, radix: 2) }
            d.solutions = stride(from: 0, to: groups.count, by: 8).map { t(groups[$0..<min($0 + 8, groups.count)].joined(separator: " ")) }
            d.whole = binary
        }
        return d
    }
}
