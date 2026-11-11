import Foundation

// Completion for a specialist calculator: one reached by a mark typed first, as @ is for astronomy.
// What follows the mark is a call, name(argument, argument); while it is being typed, a list on the
// card offers what fits where the caret is: the calculator's functions while the name is typed, and
// inside the brackets what fits that argument, bodies, values and units, never functions.
//
// Nothing here knows any astronomy. A calculator says what its functions are and what each of their
// arguments may be (a Catalogue); this reads the field, finds where the caret is in the call, matches
// loosely ("escape vel" finds escape_velocity), and says how the field reads once a choice is made.
// Positions are counted in UTF-16, as Accessibility counts them in Spotlight's field.
protocol Catalogue {
    var mark: Character { get }
    var functions: [Completion.Function] { get }
    // Everything that could be typed for this parameter, given what has been typed so far: a value
    // with each unit that fits once a number has been typed, say. Matched against it afterwards.
    func candidates(for parameter: Completion.Parameter, typed: String) -> [Completion.Item]
}

enum Completion {
    struct Function {
        var name: String                 // escape_velocity
        var forms: [[Parameter]]         // the first is what is written in when the function is chosen
        var summary: String              // a line beside it in the list
        var aliases: [String] = []       // other names it is found by: "kepler" for the orbital period

        // The form whose arguments are being typed: the one with as many as there are, or the
        // first with room for one more.
        func form(arguments: Int) -> [Parameter] {
            forms.first { $0.count == arguments } ?? forms.first { $0.count >= arguments } ?? forms[0]
        }
    }

    struct Parameter: Equatable {
        var name: String     // what stands in its place until it is typed over: body, M, d
        var kind: String     // what it may be, as the calculator understands it: "mass", "body"
    }

    struct Item: Equatable {
        var title: String          // as listed: escape_velocity(body), earth, 10 M☉
        var detail: String         // beside it: what it is
        var insertion: String      // what it writes in the field
        var keys: [String] = []    // what else it is found by, besides its insertion
        var function: String? = nil   // the function it is, for a function
        var kind: String? = nil       // the kind of argument it was offered as, for an argument
        var remembered: String? = nil // what its uses are counted under, where not its insertion: a unit, whatever the number before it
        var group = 0                 // the form of the function it was offered for, the first form's first
    }

    // Where the caret is in the call.
    enum Stage: Equatable {
        case function                                        // the name is being typed
        case argument(function: String, index: Int, parameter: Parameter)
    }

    // The list as it stands: what is offered, which is chosen, and what a choice replaces.
    struct List: Equatable {
        var text: String
        var stage: Stage
        var fragment: String          // what has been typed of the name or argument, up to the caret
        var replaced: NSRange         // what a choice writes over: the whole name, or the whole argument
        var items: [Item]
        var selected = 0
        var parameters: [Parameter] = []   // what the argument may be, in each form of the function that fits

        // What is being chosen: the parameter the chosen item fits.
        var parameter: Parameter? {
            let kind = items.indices.contains(selected) ? items[selected].kind : nil
            return parameters.first { $0.kind == kind } ?? parameters.first
        }
    }

    // What the field becomes on a choice, and what is selected in it afterwards.
    struct Edit: Equatable {
        var text: String
        var selection: NSRange
    }

    // MARK: - Reading the field

    // The list for the field as it is, with the caret (a UTF-16 offset) where it is; nil where there
    // is nothing to offer, the mark not typed first or the call closed.
    static func list(_ text: String, caret: Int? = nil, in catalogue: Catalogue) -> List? {
        let ns = text as NSString
        let caret = min(max(caret ?? ns.length, 0), ns.length)
        var start = 0
        while start < ns.length, isSpace(ns.character(at: start)) { start += 1 }
        guard start < ns.length, ns.substring(with: NSRange(location: start, length: 1)) == String(catalogue.mark), caret > start else { return nil }
        let body = start + 1
        // Arrays, objects and quoted filenames do not introduce function argument commas.
        var stack: [(at: Int, delimiter: unichar, commas: [Int])] = []
        var quote: unichar?, escaped = false
        for i in body..<caret {
            let c = ns.character(at: i)
            if let q = quote {
                if escaped { escaped = false } else if c == 0x5c { escaped = true } else if c == q { quote = nil }
                continue
            }
            if c == 0x22 || c == 0x27 { quote = c; continue }
            if [0x28,0x5b,0x7b].contains(c) { stack.append((i,c,[])) }
            else if [0x29,0x5d,0x7d].contains(c) { if !stack.isEmpty { stack.removeLast() } else { return nil } }
            else if c == 0x2c, !stack.isEmpty { stack[stack.count-1].commas.append(i) }
        }
        guard quote == nil else { return nil }
        func functions(from: Int, fragment: String) -> List? {
            var to = caret
            while to < ns.length, isWordUnit(ns.character(at: to)) { to += 1 }
            let items = ranked(catalogue.functions.map(item), fragment, mark: catalogue.mark)
            guard !items.isEmpty else { return nil }
            return List(text: text, stage: .function, fragment: fragment, replaced: NSRange(location: from, length: to-from), items: items)
        }
        if stack.isEmpty {
            let typed = ns.substring(with: NSRange(location: body, length: caret-body))
            guard typed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == " " }) else { return nil }
            let leading = typed.prefix { $0 == " " }.utf16.count
            return functions(from: body+leading, fragment: String(typed.dropFirst(leading)))
        }
        guard let call = stack.last, call.delimiter == 0x28 else { return nil }
        var nameStart = call.at
        while nameStart > body, isWordUnit(ns.character(at: nameStart-1)) { nameStart -= 1 }
        let name = ns.substring(with: NSRange(location: nameStart, length: call.at-nameStart)).lowercased()
        guard let function = catalogue.functions.first(where: { $0.name == name || $0.aliases.contains(name) }) else { return nil }
        var from = (call.commas.last ?? call.at)+1
        while from < caret, isSpace(ns.character(at: from)) { from += 1 }
        var to = caret, depth = 0
        var nextQuote: unichar?, slash = false
        while to < ns.length {
            let c = ns.character(at: to)
            if let q = nextQuote {
                if slash { slash = false } else if c == 0x5c { slash = true } else if c == q { nextQuote = nil }
            } else if c == 0x22 || c == 0x27 { nextQuote = c }
            else if [0x28,0x5b,0x7b].contains(c) { depth += 1 }
            else if [0x29,0x5d,0x7d].contains(c) { if depth == 0 { break }; depth -= 1 }
            else if c == 0x2c, depth == 0 { break }
            to += 1
        }
        while to > from, isSpace(ns.character(at: to-1)) { to -= 1 }
        var fragment = caret > from ? ns.substring(with: NSRange(location: from, length: caret-from)) : ""
        var index = call.commas.count
        // Named optional arguments select their schema regardless of positional count.
        if let equal = fragment.firstIndex(of: "=") {
            let key = fragment[..<equal].trimmingCharacters(in: .whitespaces)
            if let all = function.forms.last, let named = all.firstIndex(where: { $0.name == key }) {
                index = named
                from += fragment[..<fragment.index(after: equal)].utf16.count
                while from < caret, isSpace(ns.character(at: from)) { from += 1 }
                fragment = ns.substring(with: NSRange(location: from,length: caret-from))
            }
        }
        let parameters = function.forms.filter { $0.count > index }.map { $0[index] }
        guard let parameter = parameters.first else { return nil }
        let whole = ns.substring(with: NSRange(location: from, length: max(0,to-from)))
        let typed = parameters.contains { $0.name == whole } ? "" : fragment
        if parameter.kind == "orbit_object", !typed.isEmpty, !typed.contains("(") {
            let matching = catalogue.functions.filter { $0.name == "orbit" || $0.name == "propagate_orbit" }
            if matching.contains(where: { score(typed,$0.name) != nil }) { return functions(from: from,fragment: typed) }
        }
        var candidates: [Item] = []
        for (g,p) in parameters.enumerated() {
            for var candidate in catalogue.candidates(for:p,typed:typed) where !candidates.contains(where: { $0.insertion == candidate.insertion }) {
                candidate.kind = p.kind; candidate.group = g; candidates.append(candidate)
            }
        }
        let items = ranked(candidates,typed,mark:catalogue.mark)
        if !typed.isEmpty, caret >= to, items.contains(where: { normal($0.insertion) == normal(typed) }) { return nil }
        guard !items.isEmpty else { return nil }
        return List(text:text,stage:.argument(function:function.name,index:index,parameter:parameter),fragment:typed,
                    replaced:NSRange(location:from,length:max(0,to-from)),items:items,parameters:parameters)
    }

    static func item(_ f: Function) -> Item {
        Item(title: "\(f.name)(\(f.forms[0].map(\.name).joined(separator: ", ")))", detail: f.summary, insertion: f.name,
             keys: f.aliases, function: f.name)
    }

    // MARK: - Choosing

    // The field once the chosen item is written in. A function is written with its arguments'
    // placeholders, the first selected to be typed over; an argument goes in its place, and then
    // the next placeholder is selected, or, after the last, the caret goes past the closing bracket.
    static func apply(_ list: List, in catalogue: Catalogue, choosing index: Int? = nil) -> Edit? {
        let pick = index ?? list.selected
        guard list.items.indices.contains(pick) else { return nil }
        let item = list.items[pick]
        let ns = list.text as NSString
        let after = list.replaced.location + list.replaced.length

        switch list.stage {
        case .function:
            guard let function = catalogue.functions.first(where: { $0.name == item.function }) else { return nil }
            // Brackets already there are kept, and the caret goes inside them.
            if after < ns.length, ns.character(at: after) == 0x28 {
                let text = ns.replacingCharacters(in: list.replaced, with: function.name)
                return Edit(text: text, selection: NSRange(location: list.replaced.location + (function.name as NSString).length + 1, length: 0))
            }
            let placeholders = function.forms[0].map(\.name)
            // Straight after the mark, a space first: @ schwarzschild(body), as it reads best.
            let spaced = list.replaced.location > 0 && ns.substring(with: NSRange(location: list.replaced.location - 1, length: 1)) == String(catalogue.mark)
            let call = (spaced ? " " : "") + function.name + "(" + placeholders.joined(separator: ", ") + ")"
            let text = ns.replacingCharacters(in: list.replaced, with: call)
            let first = list.replaced.location + (spaced ? 1 : 0) + (function.name as NSString).length + 1
            return Edit(text: text, selection: NSRange(location: first + (placeholders.isEmpty ? 1 : 0), length: (placeholders.first.map { $0 as NSString }?.length) ?? 0))

        case .argument(let name, let index, _):
            let insertion = item.insertion
            var rest = ns.substring(from: after)
            // A call left open at the end is closed, with the placeholders of any arguments still to come.
            if rest.trimmingCharacters(in: .whitespaces).isEmpty, let function = catalogue.functions.first(where: { $0.name == name || $0.aliases.contains(name) }) {
                // The form the choice belongs to: orbital_period(1.5 AU, M) for a distance, (earth) for a body.
                let form = function.forms.first { $0.count > index && $0[index].kind == item.kind } ?? function.form(arguments: index + 1)
                rest = (index + 1 < form.count ? ", " + form[(index + 1)...].map(\.name).joined(separator: ", ") : "") + ")"
            }
            let text = ((ns.substring(to: list.replaced.location) + insertion + rest) as NSString)
            var caret = list.replaced.location + (insertion as NSString).length
            // The next argument, if it is still its placeholder, is selected to be typed over.
            if let function = catalogue.functions.first(where: { $0.name == name || $0.aliases.contains(name) }) {
                var k = caret
                while k < text.length, isSpace(text.character(at: k)) { k += 1 }
                if k < text.length, text.character(at: k) == 0x2C {
                    k += 1
                    while k < text.length, isSpace(text.character(at: k)) { k += 1 }
                    var end = k
                    while end < text.length, text.character(at: end) != 0x2C, text.character(at: end) != 0x29 { end += 1 }
                    let next = text.substring(with: NSRange(location: k, length: end - k)).trimmingCharacters(in: .whitespaces)
                    let placeholders = function.forms.compactMap { $0.count > index + 1 ? $0[index + 1].name : nil }
                    if placeholders.contains(next) { return Edit(text: text as String, selection: NSRange(location: k, length: (next as NSString).length)) }
                } else if k < text.length, text.character(at: k) == 0x29 {
                    caret = k + 1
                }
            }
            return Edit(text: text as String, selection: NSRange(location: caret, length: 0))
        }
    }

    // MARK: - Matching

    // The items that match what was typed, best first; among those that match as well, the ones
    // chosen most often, and then in alphabetical order (those of the function's first form before
    // the rest). With nothing typed, everything, in that order.
    static func ranked(_ items: [Item], _ typed: String, mark: Character) -> [Item] {
        let query = typed.trimmingCharacters(in: .whitespaces)
        let counts = uses
        var scored: [(item: Item, score: Int, uses: Int)] = []
        for item in items {
            let names = [item.insertion, item.title] + item.keys
            let best = query.isEmpty ? 0 : names.compactMap({ score(query, $0) }).max()
            if let best {
                // A canonical name typed in full wins over another function's alias, even if
                // that older choice has been used more often (redshift versus redshift_velocity).
                let canonical = score(query, item.insertion) == 1000 ? 1 : 0
                scored.append((item, best + canonical, counts[key(item, mark: mark)] ?? 0))
            }
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.uses != b.uses { return a.uses > b.uses }
            if a.item.group != b.item.group { return a.item.group < b.item.group }
            return a.item.title.localizedStandardCompare(b.item.title) == .orderedAscending
        }
        return scored.map(\.item)
    }

    // MARK: - What is chosen most

    // How many times each item has been chosen, kept in the defaults; Reset All Settings forgets it.
    static let usesKey = "completionUses"
    static var uses: [String: Int] { UserDefaults.standard.dictionary(forKey: usesKey) as? [String: Int] ?? [:] }

    // Counted by calculator, and as a function or an argument: @f:escape_velocity, @a:earth, @a:unit M☉.
    static func key(_ item: Item, mark: Character) -> String {
        "\(mark)\(item.function == nil ? "a" : "f"):\(item.remembered ?? item.insertion)"
    }

    // The chosen item written in, and counted, so that it comes sooner next time.
    static func choose(_ list: List, in catalogue: Catalogue) -> Edit? {
        guard let edit = apply(list, in: catalogue), list.items.indices.contains(list.selected) else { return nil }
        var counts = uses
        counts[key(list.items[list.selected], mark: catalogue.mark), default: 0] += 1
        UserDefaults.standard.set(counts, forKey: usesKey)
        return edit
    }

    // How well what was typed matches a name, or nil where it does not. Best of all, the name is
    // it; then the name begins with it; then each word typed begins a word of the name, in order ("escape vel",
    // "orb per"); last, its letters appear in the name in order ("schw", "swzs"), better the more of
    // them stand together or at the starts of words.
    static func score(_ typed: String, _ name: String) -> Int? {
        let q = typed.lowercased(), n = name.lowercased()
        let qJoined = q.filter { !isSeparator($0) }, nJoined = n.filter { !isSeparator($0) }
        guard !qJoined.isEmpty else { return nil }
        if n == q || nJoined == qJoined { return 1000 }
        // Among names it begins, the calculator's own order stands: 1.5 AU before 1.5 m for an orbit.
        if n.hasPrefix(q) || nJoined.hasPrefix(qJoined) { return 900 }

        let qWords = q.split(whereSeparator: isSeparator).map(String.init)
        let nWords = n.split(whereSeparator: isSeparator).map(String.init)
        if qWords.count > 1 || nWords.count > 1 {
            var w = 0, matched = true
            for word in qWords {
                while w < nWords.count, !nWords[w].hasPrefix(word) { w += 1 }
                if w == nWords.count { matched = false; break }
                w += 1
            }
            if matched { return 700 }
        }

        // Letters in order, the first beginning a word ("ear" finds earth, not near), each after it
        // found as early as it can be; scored by how many stand together and begin words.
        let letters = Array(nJoined), starts = Set(wordStarts(n))
        guard let first = starts.sorted().first(where: { letters[$0] == qJoined.first! }) else { return nil }
        var at = first, total = 0, previous = -2
        for c in qJoined {
            while at < letters.count, letters[at] != c { at += 1 }
            guard at < letters.count else { return nil }
            total += at == previous + 1 ? 6 : 1
            if starts.contains(at) { total += 4 }
            previous = at
            at += 1
        }
        return 100 + total * 10 - min(letters.count, 99)
    }

    // Where each word of a name begins, counted in the name with its separators taken out.
    private static func wordStarts(_ name: String) -> [Int] {
        var out: [Int] = [], k = 0, boundary = true
        for c in name {
            if isSeparator(c) { boundary = true; continue }
            if boundary { out.append(k) }
            boundary = false
            k += 1
        }
        return out
    }

    private static func isSeparator(_ c: Character) -> Bool { c == "_" || c == " " || c == "-" }
    private static func isSpace(_ u: unichar) -> Bool { u == 0x20 || u == 0x09 }
    private static func isWordUnit(_ u: unichar) -> Bool {
        (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x5F
    }
    private static func normal(_ s: String) -> String { s.lowercased().filter { !$0.isWhitespace } }
}
