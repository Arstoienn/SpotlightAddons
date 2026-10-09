import Foundation

// 750 USD to NTD, 750USD=NTD?, $20 in yen, 0.5 btc to usd, 2 oz gold to twd: an amount of money,
// a coin or a metal said in another. The rates are fetched as they stand, in the background, each
// against the US dollar: currencies from open.er-api.com (once a day), coins from api.coinbase.com
// and metals from api.gold-api.com (as they trade). The card is answered from the last that were
// had, and made again when fresh ones arrive. With no connection the last rates recorded are used,
// and the card says when they were recorded: that is said only then.
enum Rates {
    enum Group: String, CaseIterable, Codable {
        case fiat, crypto, metals
        var source: String {
            switch self {
            case .fiat: "open.er-api.com"
            case .crypto: "api.coinbase.com"
            case .metals: "api.gold-api.com"
            }
        }
        var name: String { self == .fiat ? "currency" : self == .crypto ? "coin" : "metal" }
    }

    struct Saved: Codable {
        var recorded: [String: Double]     // when each group was had, seconds since 1970
        var perDollar: [String: Double]    // how many of each one dollar buys
    }

    // Said when new rates have been had, or the connection has been found to be lost.
    static let changed = Notification.Name("SpotlightAddonsRatesChanged")

    private static var saved: Saved? = {
        guard let data = UserDefaults.standard.data(forKey: "rates") else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }()
    private static var failed: Set<Group> = []
    private static var lastTry: [Group: Date] = [:]
    private static var fetching = false
    // Set by the tests, which are to ask nothing of the network.
    static var fixed = false

    static func group(of code: String) -> Group {
        Currency.metals.contains(code) ? .metals : Currency.coins.contains(code) ? .crypto : .fiat
    }

    static var table: [String: Double]? { saved?.perDollar }
    // Whether the rates of this one have not come yet: none were saved, and none has been refused.
    static func pending(_ code: String) -> Bool {
        let g = group(of: code)
        return saved?.recorded[g.rawValue] == nil && !failed.contains(g)
    }
    static func refused(_ code: String) -> Bool { failed.contains(group(of: code)) && saved?.recorded[group(of: code).rawValue] == nil }
    // Whether any of these has had to be taken from the last had, with no connection to the source.
    static func isOffline(_ codes: [String]) -> Bool { codes.contains { failed.contains(group(of: $0)) } }
    // The oldest of when the sources of these were last had.
    static func recorded(_ codes: [String]) -> Date? {
        codes.compactMap { saved?.recorded[group(of: $0).rawValue] }.min().map { Date(timeIntervalSince1970: $0) }
    }
    // For the status page: when this group was last had, and whether the last try failed.
    static func state(_ g: Group) -> (recorded: Date?, offline: Bool) {
        (saved?.recorded[g.rawValue].map { Date(timeIntervalSince1970: $0) }, failed.contains(g))
    }
    static func sources(_ codes: [String]) -> [String] {
        var out: [String] = []
        for code in codes { let s = group(of: code).source; if !out.contains(s) { out.append(s) } }
        return out
    }

    // For the tests: rates as if had at the time, with or without a connection.
    static func install(_ perDollar: [String: Double], recorded: Date, offline: Bool) {
        fixed = true
        let stamp = recorded.timeIntervalSince1970
        saved = Saved(recorded: Dictionary(uniqueKeysWithValues: Group.allCases.map { ($0.rawValue, stamp) }), perDollar: perDollar)
        failed = offline ? Set(Group.allCases) : []
    }
    static func installNothing(offline: Bool) { fixed = true; saved = nil; failed = offline ? Set(Group.allCases) : [] }

    // How long before a group is asked for again. The currencies come from a source that has them
    // once a day and asks to be asked no oftener than once an hour (a request too soon is refused for
    // twenty minutes); coins and metals move all the time and their sources do not limit it. After a
    // failure the wait is shorter, but not for the currencies' source, which would only refuse again.
    private static func wait(_ g: Group) -> TimeInterval {
        let failedNow = failed.contains(g)
        switch g {
        case .fiat: return failedNow ? (saved?.recorded[g.rawValue] == nil ? 30 : 300) : 3600
        case .crypto, .metals: return failedNow ? 15 : 30
        }
    }

    // Asks for fresh rates, those of each group that have not been asked for lately. Never waits for them.
    static func refresh() {
        let now = Date()
        let due = Group.allCases.filter { now.timeIntervalSince(lastTry[$0] ?? .distantPast) > wait($0) }
        guard !fixed, !fetching, !due.isEmpty else { return }
        fetching = true
        for g in due { lastTry[g] = now }
        let lock = NSLock(), done = DispatchGroup()
        var got: [Group: [String: Double]] = [:]

        func ask(_ address: String, _ then: @escaping (Any) -> [String: Double]?, group: Group) {
            guard let url = URL(string: address) else { return }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            done.enter()
            URLSession.shared.dataTask(with: request) { data, response, _ in
                defer { done.leave() }
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let object = try? JSONSerialization.jsonObject(with: data), let rates = then(object) else { return }
                lock.lock(); got[group, default: [:]].merge(rates) { $1 }; lock.unlock()
            }.resume()
        }
        if due.contains(.fiat) { ask("https://open.er-api.com/v6/latest/USD", { object in
            guard let o = object as? [String: Any], o["result"] as? String == "success", let r = o["rates"] as? [String: Double], r["USD"] == 1 else { return nil }
            return r
        }, group: .fiat) }
        if due.contains(.crypto) { ask("https://api.coinbase.com/v2/exchange-rates?currency=USD", { object in
            guard let o = (object as? [String: Any])?["data"] as? [String: Any], let r = o["rates"] as? [String: String] else { return nil }
            let found = r.compactMap { key, value -> (String, Double)? in
                guard Currency.coins.contains(key), let v = Double(value), v > 0 else { return nil }
                return (key, v)
            }
            return found.isEmpty ? nil : Dictionary(uniqueKeysWithValues: found)
        }, group: .crypto) }
        for metal in Currency.metals.sorted() where due.contains(.metals) {
            ask("https://api.gold-api.com/price/\(metal)", { object in
                guard let o = object as? [String: Any], let price = o["price"] as? Double, price > 0 else { return nil }
                return [metal: 1 / price]
            }, group: .metals)
        }
        done.notify(queue: .main) {
            fetching = false
            let before = (failed, saved?.recorded)
            var next = saved ?? Saved(recorded: [:], perDollar: [:])
            for g in due {
                // Metals are had only if every one of them has come.
                let complete = g == .metals ? (got[g]?.count == Currency.metals.count) : got[g] != nil
                if complete, let rates = got[g] {
                    next.perDollar.merge(rates) { $1 }
                    next.recorded[g.rawValue] = Date().timeIntervalSince1970
                    failed.remove(g)
                } else {
                    failed.insert(g)
                }
            }
            saved = next
            if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: "rates") }
            // The card is made again only if something it shows has changed.
            if before.0 != failed || before.1 != saved?.recorded { NotificationCenter.default.post(name: changed, object: nil) }
        }
    }
}

enum Currency {
    // Every code the rates come with: any currency may be named, in any case, as the list is
    // closed and a code means nothing else. usd, Usd and USD are one.
    private static let codes: Set<String> = Set("""
        AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTN BWP BYN BZD CAD CDF CHF CLF CLP CNH CNY COP CRC CUP
        CVE CZK DJF DKK DOP DZD EGP ERN ETB EUR FJD FKP FOK GBP GEL GGP GHS GIP GMD GNF GTQ GYD HKD HNL HRK HTG HUF IDR ILS IMP INR IQD IRR ISK JEP
        JMD JOD JPY KES KGS KHR KID KMF KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO
        NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SLL SOS SRD SSP STN SYP SZL THB TJS TMT TND
        TOP TRY TTD TVD TWD TZS UAH UGX USD UYU UZS VES VND VUV WST XAF XCD XCG XDR XOF XPF YER ZAR ZMW ZWG ZWL
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    // The coins and metals that may be named. A coin is by its usual code; a metal is priced by
    // the troy ounce. The lists are short on purpose: a code that is a word is left out.
    static let coins: Set<String> = ["BTC", "ETH", "USDT", "USDC", "BNB", "XRP", "SOL", "ADA", "DOGE", "DOT", "LTC", "AVAX", "LINK", "POL", "SHIB", "ATOM",
                                     "UNI", "XLM", "BCH", "ETC", "APT", "SUI", "PEPE", "DAI", "WBTC", "HBAR", "FIL", "ICP", "AAVE", "INJ", "ALGO", "XTZ", "EOS"]
    static let metals: Set<String> = ["XAU", "XAG", "XPT", "XPD"]

    // And what else a currency is called: a symbol, or a name that is only its own.
    private static let names: [String: String] = {
        var t: [String: String] = [:]
        let more: [String: [String]] = [
            "USD": ["us$", "dollar", "dollars", "us dollar", "us dollars", "american dollar", "american dollars"],
            "EUR": ["€", "euro", "euros"],
            "GBP": ["£", "sterling", "pound sterling", "pounds sterling", "british pound", "british pounds"],
            "JPY": ["¥", "￥", "yen", "japanese yen"],
            "CNY": ["rmb", "yuan", "renminbi", "cn¥"],
            "HKD": ["hk$", "hong kong dollar", "hong kong dollars"],
            "TWD": ["ntd", "nt", "nt$", "ntd$", "nt dollar", "nt dollars", "new taiwan dollar", "new taiwan dollars", "taiwan dollar", "taiwan dollars"],
            "KRW": ["₩", "won", "korean won"],
            "AUD": ["a$", "au$", "australian dollar", "australian dollars"],
            "CAD": ["c$", "ca$", "canadian dollar", "canadian dollars"],
            "CHF": ["swiss franc", "swiss francs"],
            "SGD": ["s$", "singapore dollar", "singapore dollars"],
            "NZD": ["nz$", "new zealand dollar", "new zealand dollars"],
            "THB": ["฿", "baht"], "MYR": ["rm", "ringgit"], "INR": ["₹", "indian rupee", "indian rupees"],
            "RUB": ["₽", "ruble", "rubles", "rouble", "roubles"], "VND": ["₫", "dong"],
            "BRL": ["r$", "real", "reais"], "MXN": ["mx$", "mex$"], "ZAR": ["rand"], "PLN": ["zł", "zloty"], "CZK": ["kč", "koruna"],
            "TRY": ["₺", "lira"], "ILS": ["₪", "shekel", "shekels"], "UAH": ["₴", "hryvnia"], "NGN": ["₦", "naira"], "PHP": ["₱"],
            "IDR": ["rp", "rupiah"], "AED": ["dirham", "dirhams"], "SAR": ["riyal", "riyals"],
        ]
        let others: [String: [String]] = [
            "BTC": ["₿", "bitcoin", "bitcoins"], "ETH": ["ether", "ethereum"], "USDT": ["tether"], "DOGE": ["dogecoin"], "LTC": ["litecoin"],
            "SOL": ["solana"], "XRP": ["ripple"], "ADA": ["cardano"], "DOT": ["polkadot"], "XLM": ["stellar"],
            "XAU": ["gold"], "XAG": ["silver"], "XPT": ["platinum"], "XPD": ["palladium"],
        ]
        for (code, words) in more.merging(others, uniquingKeysWith: { $0 + $1 }) { for w in words { t[w] = code } }
        return t
    }()

    // Currencies that are kept in whole units, and those in thousandths.
    private static let whole: Set<String> = ["JPY", "KRW", "VND", "IDR", "CLP", "ISK", "HUF", "COP", "PKR", "BIF", "DJF", "GNF", "KMF", "PYG", "RWF", "UGX", "VUV", "XAF", "XOF", "XPF"]
    private static let thousandths: Set<String> = ["KWD", "BHD", "OMR", "JOD", "TND", "IQD", "LYD"]

    static func code(_ text: String) -> String? {
        let key = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let named = names[key] { return named }
        let upper = key.uppercased()
        if codes.contains(upper) || coins.contains(upper) || metals.contains(upper) { return upper }
        if upper.count == 3 && Rates.table?[upper] != nil { return upper }
        return misspelt(key)
    }

    // A name with a letter wrong, left out, added or swapped (glod, bitcon, sterlign) is the one name it is
    // a slip of, if there is only one. Short names are never guessed at, nor anything with a digit.
    private static func misspelt(_ key: String) -> String? {
        guard key.count >= 4, key.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let found = Set(names.filter { $0.key.count >= 4 && $0.key.allSatisfy { $0.isASCII && $0.isLetter } && slip(key, $0.key) }.map(\.value))
        return found.count == 1 ? found.first : nil
    }

    // Whether two words are one slip apart: a letter changed, left out, added, or two side by side swapped.
    private static func slip(_ a: String, _ b: String) -> Bool {
        let (x, y) = (Array(a), Array(b))
        guard x != y, abs(x.count - y.count) <= 1 else { return false }
        if x.count == y.count {
            let differ = x.indices.filter { x[$0] != y[$0] }
            if differ.count == 1 { return true }
            return differ.count == 2 && differ[1] == differ[0] + 1 && x[differ[0]] == y[differ[1]] && x[differ[1]] == y[differ[0]]
        }
        let (long, short) = x.count > y.count ? (x, y) : (y, x)
        var i = 0
        while i < short.count, long[i] == short[i] { i += 1 }
        return Array(long[(i + 1)...]) == Array(short[i...])
    }

    // How many places an amount is given to: cents, or whole units or thousandths for those kept so;
    // for a coin or a metal as many as are of use, at least two.
    private static func places(_ code: String, _ v: Double) -> (least: Int, most: Int) {
        if whole.contains(code) { return (0, 0) }
        if thousandths.contains(code) { return (3, 3) }
        if coins.contains(code) || metals.contains(code) { return abs(v) >= 1000 ? (2, 2) : abs(v) >= 1 ? (2, 4) : (2, 8) }
        return abs(v) < 1 && v != 0 ? (4, 4) : (2, 2)
    }

    // 23,664.23: with commas between the thousands, to the places the currency is given to.
    static func money(_ v: Double, _ code: String, cap: Int = 8) -> String {
        // 23664.224999999997 is 23664.225: the float's last places are not money.
        let v = Double(String(format: "%.12g", v)) ?? v
        var p = places(code, v)
        p.most = min(p.most, cap)
        let f = NumberFormatter()
        f.roundingMode = .halfUp
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = p.least
        f.maximumFractionDigits = p.most
        return (f.string(from: NSNumber(value: v)) ?? String(format: "%.\(p.most)f", v)).replacingOccurrences(of: "-", with: "−")
    }

    // What is copied: the amount to the places it is shown to.
    static func rounded(_ v: Double, _ code: String) -> Double {
        let scale = pow(10, Double(places(code, v).most))
        return (Double(String(format: "%.12g", v * scale)) ?? v * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: date)
    }

    static func conversion(_ typed: String) -> Conversion? { Options.conversions ? parse(typed) : nil }

    static func parse(_ input: String) -> Conversion? {
        var text = input.trimmingCharacters(in: .whitespaces)
        // "= ?" or "?" at the end only asks.
        while let last = text.last, last == "?" || last == "=" || last == " " { text.removeLast() }
        guard !text.isEmpty else { return nil }
        // Where the connector may be, the last first. "=" is one only between a sum of money and
        // a currency, which is checked by what stands on either side of it.
        var splits: [Range<String.Index>] = []
        for word in [" to ", " in ", " into ", " as ", "->", "→", "=>", "="] {
            var from = text.startIndex
            while let r = text.range(of: word, options: .caseInsensitive, range: from..<text.endIndex) {
                splits.append(r)
                from = text.index(after: r.lowerBound)
            }
        }
        for split in splits.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            guard let (to, unit) = target(String(text[split.upperBound...])) else { continue }
            let left = String(text[..<split.lowerBound])
            guard let (amount, expr, from, written) = amountAndCurrency(left) else { continue }
            // Without an amount it is a rate asked for, which "=" is not enough to say.
            if written.isEmpty, text[split] == "=" { continue }
            return built(amount, expr, from: from, to: to, unit: unit, typed: written, text: input)
        }
        return nil
    }

    // What it is said in: a currency, or a metal by the gram, the kilogram or the ounce (gold g, g of gold,
    // grams of silver, xau oz). The unit is given as its name and how many of it are in a troy ounce.
    private static func target(_ typed: String) -> (String, (label: String, perOunce: Double)?)? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        if let code = code(text) { return (code, nil) }
        // An ounce by itself, said of money, is the troy ounce of gold.
        if ["oz", "ounce", "ounces", "troy ounce", "troy ounces", "troy oz"].contains(text.lowercased()) { return ("XAU", ("oz gold", 1)) }
        let units: [(names: [String], label: String, perOunce: Double)] = [
            (["g", "gram", "grams"], "g", 31.1034768), (["kg", "kilogram", "kilograms", "kilo", "kilos"], "kg", 0.0311034768),
            (["oz", "ounce", "ounces", "troy ounce", "troy ounces", "troy oz"], "oz", 1),
        ]
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 2 else {
            // Joined: goldg is not a word, but gold-g and gold/g might be.
            return nil
        }
        // The unit first or last, with "of" between if it is first.
        for cut in 1..<words.count {
            var head = words[..<cut].joined(separator: " "), tail = words[cut...].joined(separator: " ")
            for (first, second) in [(head, tail), (tail, head)] {
                var unitWord = first, metalWord = second
                if let m = metalWord.range(of: "^of\\s+", options: [.regularExpression, .caseInsensitive]) { metalWord.removeSubrange(m) }
                if let m = unitWord.range(of: "\\s+of$", options: [.regularExpression, .caseInsensitive]) { unitWord.removeSubrange(m) }
                guard let metal = code(metalWord), metals.contains(metal),
                      let unit = units.first(where: { $0.names.contains(unitWord.lowercased()) }) else { continue }
                let name = ["XAU": "gold", "XAG": "silver", "XPT": "platinum", "XPD": "palladium"][metal]!
                return (metal, ("\(unit.label) \(name)", unit.perOunce))
            }
            head = ""; tail = ""
        }
        return nil
    }

    // 750 USD, $750, 750*2 usd, usd: the amount (1 where none is given), and the currency.
    private static func amountAndCurrency(_ left: String) -> (Double, Expr?, String, String)? {
        var left = left.trimmingCharacters(in: .whitespaces)
        // 2 oz gold, 2 troy ounces of gold: the ounce is the metal's own unit. 10 g gold, 1 kg of silver
        // are said in grams, of which there are 31.1035 to the troy ounce.
        left = left.replacingOccurrences(of: "(?i)\\s*(?<![a-z])(?:troy\\s+)?(?:oz|ounces?)\\.?\\s+(?:of\\s+)?(gold|silver|platinum|palladium)$", with: " $1", options: .regularExpression)
        if let m = left.range(of: "(?i)\\s*(?<![a-z])(g|grams?|kg|kilograms?)\\s+(?:of\\s+)?(gold|silver|platinum|palladium)$", options: .regularExpression) {
            let head = String(left[..<m.lowerBound]), tail = String(left[m]).trimmingCharacters(in: .whitespaces).split(separator: " ")
            let grams = tail[0].lowercased().hasPrefix("k") ? "1000" : "1"
            left = "(\(head))*\(grams)/31.1034768 \(tail.last!)"
        }
        // 1,000 and 1 000 are one thousand.
        left = left.replacingOccurrences(of: "(?<=\\d),(?=\\d{3}(?!\\d))", with: "", options: .regularExpression)
        if left.rangeOfCharacter(from: .decimalDigits) == nil, let (code, unit) = target(left) {
            // gold oz is one ounce of it, gold g one gram.
            return (1 / (unit?.perOunce ?? 1), nil, code, "")
        }
        // A symbol before the amount: $750, NT$750, €20.
        if let m = left.range(of: "^(nt\\$|ntd\\$|hk\\$|us\\$|a\\$|au\\$|c\\$|ca\\$|s\\$|nz\\$|mx\\$|mex\\$|r\\$|cn¥|rm|rp|\\$|€|£|₿|¥|￥|₩|₹|₽|₺|฿|₫|₱|₪|₴|₦)\\s*", options: [.regularExpression, .caseInsensitive]) {
            let symbol = String(left[m]).trimmingCharacters(in: .whitespaces)
            let rest = String(left[m.upperBound...])
            let key = symbol == "$" ? "us$" : symbol
            if let c = code(key), let expr = try? Parser.constant(rest), !expr.hasUnknown, expr.eval(0).isFinite {
                return (expr.eval(0), expr, c, symbol)
            }
        }
        // The currency first, and then the amount: jpy 10, usd 750.
        let lead = Array(left)
        for j in lead.indices where j > 0 {
            guard !(lead[j - 1].isLetter && lead[j].isLetter && lead[j - 1].isASCII && lead[j].isASCII) else { continue }
            let name = String(lead[..<j]).trimmingCharacters(in: .whitespaces), rest = String(lead[j...])
            guard !name.isEmpty, name.rangeOfCharacter(from: .decimalDigits) == nil, let c = code(name),
                  rest.rangeOfCharacter(from: .decimalDigits) != nil, let expr = try? Parser.constant(rest), !expr.hasUnknown, expr.eval(0).isFinite else { continue }
            return (expr.eval(0), expr, c, name)
        }
        // The amount, and then the name of the currency at the end of what is left of the connector.
        let chars = Array(left)
        for i in chars.indices where i > 0 {
            guard !(chars[i - 1].isLetter && chars[i].isLetter && chars[i - 1].isASCII && chars[i].isASCII) else { continue }
            let head = String(chars[..<i]).trimmingCharacters(in: .whitespaces), tail = String(chars[i...])
            guard !head.isEmpty, let (c, unit) = target(tail), unit == nil || Currency.metals.contains(c),
                  let expr = try? Parser.constant(head), !expr.hasUnknown, expr.eval(0).isFinite else { continue }
            // 2 gold oz is two ounces, and 10 gold g ten grams, of which there are 31.1035 to the ounce.
            return (expr.eval(0) / (unit?.perOunce ?? 1), expr, c, tail.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func built(_ amount: Double, _ expr: Expr?, from: String, to: String, unit: (label: String, perOunce: Double)? = nil, typed: String, text: String) -> Conversion {
        Rates.refresh()
        let equation = t(text.trimmingCharacters(in: .whitespaces))
        guard let table = Rates.table, let a = table[from], let b = table[to], a > 0, b > 0 else {
            // No rates, or none for these.
            let missing = Rates.table?[from] == nil ? from : to
            let (exact, why) = Rates.pending(missing) ? ("Fetching the rates", "One moment: the card is made again when they arrive.")
                : Rates.refused(missing) ? ("No rates saved", "There is no connection, and no rates for \(missing) have yet been saved.")
                : ("No rate", "\(Rates.group(of: missing).source) has no rate for \(missing).")
            let d = Details(name: "", equation: equation, steps: [Step(label: "Why there is no value", math: nil, note: why)], solutions: [t(exact), t(why)], note: nil, f: { _ in .nan }, roots: [])
            var c = Conversion(value: .nan, text: exact, approx: why, details: d)
            c.copy = ""
            return c
        }
        // In grams, the ounce's price is divided among the grams in it.
        let rate = b / a * (unit?.perOunce ?? 1)
        let value = rounded(amount * rate, to)
        let toName = unit?.label ?? to
        // By the gram it is given to four places, and not eight.
        let cap = unit == nil ? 8 : 4
        let shown = "= \(money(amount * rate, to, cap: cap)) \(toName)"
        let rateText = "1 \(from) = \(decimal(rate)) \(toName)"
        // Said only when there is no connection: when the rates were recorded.
        let involved = [from, to]
        let offline = Rates.isOffline(involved)
        let since = Rates.recorded(involved).map(stamp)
        let offlineNote = offline ? since.map { "No connection: the rates recorded on \($0) are used." } : nil
        let sources = Rates.sources(involved).map { $0 == Rates.Group.fiat.source ? "\($0) (Rates By Exchange Rate API, exchangerate-api.com)" : $0 }.joined(separator: " and ")
        let perOunce = Currency.metals.contains(from) || Currency.metals.contains(to)
            ? " A metal is priced by the troy ounce, of 31.1035 g." : ""
        var d = Details(name: "", equation: t("\(money(amount, from)) \(from) → \(toName)"), steps: [], solutions: [t(shown)], note: offlineNote, f: { _ in .nan }, roots: [])
        d.steps.append(Step(label: "Taking the rate", math: t(rateText),
                            note: (from == "USD" || to == "USD" ? "" : "Each rate is against the US dollar, so the rate between these two is the ratio of theirs. ")
                                + (offlineNote ?? "The rate is the latest from \(sources).") + perOunce))
        d.steps.append(Step(label: "Multiplying", math: t("\(money(amount, from)) × \(decimal(rate)) = \(money(amount * rate, to, cap: cap)) \(toName)")))
        d.steps.append(Step(label: "Hence", math: t("\(money(amount, from)) \(from) ≈ \(money(amount * rate, to, cap: cap)) \(toName)")))
        if let offlineNote { d.solutions.append(t(offlineNote)) }
        let approx = rateText + (offline ? since.map { "  ·  offline, rates of \($0)" } ?? "" : "")
        return Conversion(value: value, text: shown, approx: approx, details: d)
    }
}
