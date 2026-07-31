import Foundation
@testable import Domain

// P1.1b: wires the real Money.swift port into FunctionRegistry so
// money.json's vectors un-skip. Registered under (domain="money",
// fn=<name>) to match tools/golden-vectors/vectors/money.json exactly --
// mirrors the Android adapter (MoneyVectors.kt) field-for-field; field
// names below (a/b, money, items, total, to/rate, etc.) were read
// directly off tools/golden-vectors/export.ts's money section, not
// guessed. Called from VectorRunnerTests.testMoney() (XCTest).
//
// Unlike the Kotlin side, no whole-number-formatting workaround is
// needed for raw numeric returns like toMajor: NSNumber's `isEqual`
// (which VectorRunnerTests.jsonEqual bridges through) compares by VALUE
// regardless of int/double representation, so a Swift Double 500.0
// already compares equal to a JSON-parsed integer 500 -- this is a
// genuine platform difference from kotlinx.serialization's JsonElement,
// which compares by textual content and needed Vectors.kt's jsonNumber()
// helper for exactly this case.
//
// format() is deliberately NOT registered here -- see Money.swift's
// header comment for why.

private func asMoney(_ any: Any) -> Money {
    let dict = any as! [String: Any]
    let amount = (dict["amount"] as! NSNumber).int64Value
    let currency = dict["currency"] as! String
    return Money(amount: amount, currency: currency)
}

private func moneyToJson(_ m: Money) -> [String: Any] {
    ["amount": String(m.amount), "currency": m.currency]
}

private func moneyArrToJson(_ ms: [Money]) -> [[String: Any]] {
    ms.map(moneyToJson)
}

func registerMoneyVectors() {
    FunctionRegistry.register(domain: "money", fn: "minorUnits") { input in
        let dict = input as! [String: Any]
        return minorUnits(dict["currency"] as! String)
    }

    FunctionRegistry.register(domain: "money", fn: "money") { input in
        let dict = input as! [String: Any]
        let amount = (dict["amount"] as! NSNumber).doubleValue
        let currency = dict["currency"] as! String
        return moneyToJson(try money(amount, currency))
    }

    FunctionRegistry.register(domain: "money", fn: "fromMajor") { input in
        let dict = input as! [String: Any]
        let value = (dict["value"] as! NSNumber).doubleValue
        let currency = dict["currency"] as! String
        return moneyToJson(fromMajor(value, currency))
    }

    FunctionRegistry.register(domain: "money", fn: "toMajor") { input in
        let dict = input as! [String: Any]
        return toMajor(asMoney(dict["money"]!))
    }

    FunctionRegistry.register(domain: "money", fn: "isZero") { input in
        let dict = input as! [String: Any]
        return isZero(asMoney(dict["money"]!))
    }

    FunctionRegistry.register(domain: "money", fn: "isNegative") { input in
        let dict = input as! [String: Any]
        return isNegative(asMoney(dict["money"]!))
    }

    FunctionRegistry.register(domain: "money", fn: "add") { input in
        let dict = input as! [String: Any]
        return moneyToJson(try add(asMoney(dict["a"]!), asMoney(dict["b"]!)))
    }

    FunctionRegistry.register(domain: "money", fn: "subtract") { input in
        let dict = input as! [String: Any]
        return moneyToJson(try subtract(asMoney(dict["a"]!), asMoney(dict["b"]!)))
    }

    FunctionRegistry.register(domain: "money", fn: "negate") { input in
        let dict = input as! [String: Any]
        return moneyToJson(negate(asMoney(dict["money"]!)))
    }

    FunctionRegistry.register(domain: "money", fn: "scale") { input in
        let dict = input as! [String: Any]
        let factor = (dict["factor"] as! NSNumber).doubleValue
        return moneyToJson(scale(asMoney(dict["money"]!), factor))
    }

    FunctionRegistry.register(domain: "money", fn: "sum") { input in
        let dict = input as! [String: Any]
        let items = (dict["items"] as! [Any]).map(asMoney)
        // "currency" is explicit JSON null in the empty-list-throws
        // vector (export.ts writes `currency: null` literally). A JSON
        // null decodes via JSONSerialization as NSNull, not Optional.none.
        let currency: String?
        if let raw = dict["currency"], !(raw is NSNull) {
            currency = raw as? String
        } else {
            currency = nil
        }
        return moneyToJson(try sum(items, currency: currency))
    }

    FunctionRegistry.register(domain: "money", fn: "convert") { input in
        let dict = input as! [String: Any]
        let to = dict["to"] as! String
        let rate = (dict["rate"] as! NSNumber).doubleValue
        return moneyToJson(try convert(asMoney(dict["money"]!), to: to, rate: rate))
    }

    FunctionRegistry.register(domain: "money", fn: "split") { input in
        let dict = input as! [String: Any]
        let total = asMoney(dict["total"]!)
        let parts = (dict["parts"] as! NSNumber).intValue
        return moneyArrToJson(try split(total, parts))
    }

    FunctionRegistry.register(domain: "money", fn: "itemsReconcile") { input in
        let dict = input as! [String: Any]
        let total = asMoney(dict["total"]!)
        let items = (dict["items"] as! [Any]).map(asMoney)
        return itemsReconcile(total, items)
    }
}
