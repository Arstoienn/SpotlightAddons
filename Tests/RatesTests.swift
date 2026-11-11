import Foundation

// Coins where Coinbase cannot be reached, as where a network blocks it: had from Kraken instead, and
// said to be. Every response is made up here, and nothing is saved. Run from Tests/main.swift.
func ratesFallbackTests() {
    let transport = Rates.transport, persist = Rates.persist
    defer { Rates.transport = transport; Rates.persist = persist; Rates.installNothing(offline: false) }
    Rates.installNothing(offline: false)
    Rates.fixed = false
    Rates.persist = { _ in }
    var coinbaseWorks = false, krakenWorks = true, asked: [String] = []
    Rates.transport = { request, complete in
        let host = request.url?.host ?? ""
        asked.append(host)
        let ok = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
        if host == "api.coinbase.com" {
            guard coinbaseWorks else { return complete(nil, nil, URLError(.serverCertificateUntrusted)) }
            let object: [String: Any] = ["data": ["currency": "USD", "rates": ["BTC": "0.00002", "ETH": "0.0005"]]]
            return complete(try? JSONSerialization.data(withJSONObject: object), ok, nil)
        }
        guard krakenWorks else { return complete(nil, nil, URLError(.notConnectedToInternet)) }
        let object: [String: Any] = ["error": [], "result": ["XXBTZUSD": ["c": ["40000.0", "1"]], "XETHZUSD": ["c": ["2500.0", "1"]]]]
        complete(try? JSONSerialization.data(withJSONObject: object), ok, nil)
    }
    func refreshed() {
        Rates.refresh(.crypto, force: true)
        let deadline = Date().addingTimeInterval(2)
        while Rates.isRefreshing && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    }

    // Coinbase refused, Kraken answers: the coins are had, from Kraken, and nothing is said to have failed.
    refreshed()
    workingCheck(asked == ["api.coinbase.com", "api.kraken.com"], "Kraken was not asked in Coinbase's place: \(asked)")
    workingCheck(Rates.table?["BTC"] == 1 / 40000.0 && Rates.table?["ETH"] == 1 / 2500.0, "Kraken's prices were not taken: \(String(describing: Rates.table))")
    workingCheck(!Rates.state(.crypto).offline, "coins had from Kraken were still said to have failed")
    workingCheck(Rates.title(.crypto) == "Cryptocurrency (Kraken, in place of Coinbase)" && Rates.sources(["BTC"]) == ["api.kraken.com"],
                 "the coins were not said to come from Kraken: \(Rates.title(.crypto)), \(Rates.sources(["BTC"]))")
    workingCheck(Currency.krakenStandIn.count > 100 && Currency.krakenStandIn["BTC"] == "XXBTZUSD", "Kraken's stand-in list is missing coins")

    // Both refused: the last had are kept, and each source's reason is given.
    krakenWorks = false
    refreshed()
    let error = Rates.state(.crypto).error ?? ""
    workingCheck(Rates.state(.crypto).offline && Rates.table?["BTC"] == 1 / 40000.0, "a failure of both lost the last rates or was not said")
    workingCheck(error.contains("api.coinbase.com:") && error.contains("api.kraken.com:"), "both sources' reasons were not given: \(error)")

    // Coinbase back: its own prices, and its own name again.
    coinbaseWorks = true; krakenWorks = true; asked = []
    refreshed()
    workingCheck(asked == ["api.coinbase.com"] && Rates.table?["BTC"] == 0.00002, "Coinbase was not used once it could be reached again")
    workingCheck(Rates.title(.crypto) == "Cryptocurrency (Coinbase)" && Rates.sources(["BTC"]) == ["api.coinbase.com"], "Coinbase's name did not come back")
}
