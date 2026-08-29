import Foundation
@testable import Domain

// Wires InstrumentCatalog.swift into FunctionRegistry.
//
// `seedInstrumentKeys` is the unusual one and the reason this corpus exists at
// all. The seed table is the only hand-transcribed DATA in this port -- 58 rows
// written out twice, once per platform -- and a search vector cannot protect
// it, because the search takes its candidate list as an argument. Pinning the
// keys makes a dropped or misspelled row a red test instead of a ticker that
// quietly exists on one phone and not the other.

private func instrumentsOf(_ input: [Any]) -> [Instrument] {
    input.map { entry in
        let i = entry as! [String: Any]
        return Instrument(
            symbol: i["symbol"] as! String,
            name: i["name"] as! String,
            exchange: i["exchange"] as! String,
            currency: i["currency"] as! String
        )
    }
}

func registerInstrumentCatalogVectors() {
    FunctionRegistry.register(domain: "instrument-catalog", fn: "seedInstrumentKeys") { _ in
        seedInstrumentKeys()
    }

    FunctionRegistry.register(domain: "instrument-catalog", fn: "instrumentKey") { input in
        let d = input as! [String: Any]
        return instrumentKey(d["symbol"] as! String, d["exchange"] as! String)
    }

    FunctionRegistry.register(domain: "instrument-catalog", fn: "knownExchanges") { input in
        let d = input as! [String: Any]
        return knownExchanges(instrumentsOf(d["list"] as! [Any]))
    }

    FunctionRegistry.register(domain: "instrument-catalog", fn: "searchInstruments") { input in
        let d = input as! [String: Any]
        // `exchange` is JSON null for "all exchanges", which JSONSerialization
        // hands over as NSNull -- `as? String` yields nil for it, so the cast
        // is the unwrap and no explicit NSNull check is needed.
        let results = searchInstruments(
            instrumentsOf(d["list"] as! [Any]),
            query: d["query"] as! String,
            exchange: d["exchange"] as? String,
            limit: (d["limit"] as! NSNumber).intValue
        )
        return results.map { instrumentKey($0.symbol, $0.exchange) }
    }
}
