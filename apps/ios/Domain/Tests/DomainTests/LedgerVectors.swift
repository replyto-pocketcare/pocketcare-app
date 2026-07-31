import Foundation
@testable import Domain

// P1.2b: wires the real Ledger.swift port into FunctionRegistry so
// ledger.json's vectors un-skip. Registered under (domain="ledger",
// fn=<name>) to match tools/golden-vectors/vectors/ledger.json exactly --
// mirrors the Android adapter (LedgerVectors.kt) field-for-field. Called
// from VectorRunnerTests.testLedger() (XCTest).

private func asMoney(_ any: Any) -> Money {
    let dict = any as! [String: Any]
    let amount = (dict["amount"] as! NSNumber).int64Value
    let currency = dict["currency"] as! String
    return Money(amount: amount, currency: currency)
}

private func moneyToJson(_ m: Money) -> [String: Any] {
    ["amount": String(m.amount), "currency": m.currency]
}

private func asLedgerEntry(_ any: Any) -> LedgerEntry {
    let dict = any as! [String: Any]
    let toAccountId: String?
    if let raw = dict["to_account_id"], !(raw is NSNull) {
        toAccountId = raw as? String
    } else {
        toAccountId = nil
    }
    let toAmount: Int64?
    if let raw = dict["to_amount"], !(raw is NSNull) {
        toAmount = (raw as? NSNumber)?.int64Value
    } else {
        toAmount = nil
    }
    return LedgerEntry(
        type: dict["type"] as! String,
        accountId: dict["account_id"] as! String,
        amount: (dict["amount"] as! NSNumber).int64Value,
        toAccountId: toAccountId,
        toAmount: toAmount
    )
}

func registerLedgerVectors() {
    FunctionRegistry.register(domain: "ledger", fn: "signedEffectFor") { input in
        let dict = input as! [String: Any]
        let entry = asLedgerEntry(dict["entry"]!)
        let accountId = dict["accountId"] as! String
        // Stringified (like a Money amount), not a raw number -- the
        // exporter treats any raw minor-unit integer as money-shaped.
        return String(signedEffectFor(entry, accountId))
    }

    FunctionRegistry.register(domain: "ledger", fn: "deriveBalance") { input in
        let dict = input as! [String: Any]
        let accountId = dict["accountId"] as! String
        let currency = dict["currency"] as! String
        let entries = (dict["entries"] as! [Any]).map(asLedgerEntry)
        return moneyToJson(deriveBalance(accountId, currency, entries))
    }

    FunctionRegistry.register(domain: "ledger", fn: "availableBalance") { input in
        let dict = input as! [String: Any]
        return moneyToJson(try availableBalance(asMoney(dict["total"]!), asMoney(dict["blocked"]!)))
    }

    FunctionRegistry.register(domain: "ledger", fn: "aggregateNetWorth") { input in
        let dict = input as! [String: Any]
        let balances = (dict["balances"] as! [Any]).map { b -> AccountBalance in
            let bd = b as! [String: Any]
            return AccountBalance(balance: asMoney(bd["balance"]!), blocked: asMoney(bd["blocked"]!))
        }
        let base = dict["base"] as! String
        let ratesDict = dict["rates"] as! [String: Any]
        let rates: [String: Double] = ratesDict.mapValues { ($0 as! NSNumber).doubleValue }
        let includeBlocked = (dict["includeBlocked"] as! NSNumber).boolValue
        // Mirrors the TS vector's own getRate closure exactly: same
        // currency short-circuits to 1, otherwise look up `rates` and
        // default to 1 if the pair isn't present.
        let getRate: RateLookup = { from, to in from == to ? 1.0 : (rates[from] ?? 1.0) }
        return moneyToJson(try aggregateNetWorth(balances, base: base, getRate: getRate, includeBlocked: includeBlocked))
    }
}
