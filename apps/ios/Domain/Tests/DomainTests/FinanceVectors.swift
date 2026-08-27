import Foundation
@testable import Domain

// P1.3b: wires the real Finance.swift port into FunctionRegistry so
// finance.json's vectors un-skip. Registered under (domain="finance",
// fn=<name>) to match tools/golden-vectors/vectors/finance.json exactly --
// mirrors the Android adapter (FinanceVectors.kt) field-for-field,
// including its money-string-vs-plain-number split (subscriptionImpact's
// and projectCashflow's money-shaped fields are NOT stringified in the
// exported vectors, unlike every other money-shaped result in this
// domain -- verified against tools/golden-vectors/export.ts's finance
// section, not guessed).

/// Infinity -> NSNull (mirrors JS's JSON.stringify(Infinity) === "null");
/// everything else -> NSNumber. Needed for periodicRateFromAnnual,
/// periodsToGoal, percentOfIncome (this domain is the first native port
/// to actually produce Infinity results). Internal (not private), not
/// file-scoped -- BudgetVectors.swift's budgetProgress.pct reuses it
/// rather than duplicating the same Infinity-handling logic twice.
///
/// **It was called `jsonNumber` and had to be renamed.** Domain later gained a
/// PUBLIC `jsonNumber(Double) -> String`, and inside this test target the
/// target's own declaration wins over the imported module's. Every
/// `jsonNumber(...)` in AssistantVectors silently called THIS instead — no
/// ambiguity error, no warning, just 41 vectors comparing a number against a
/// string. A same-named helper in a test target shadowing a public API is a
/// silent-wrong-value trap, so the local one moved.
func jsonOrNull(_ n: Double) -> Any {
    n.isFinite ? NSNumber(value: n) : NSNull()
}

private func asRecurringLike(_ any: Any) -> RecurringLike {
    let d = any as! [String: Any]
    return RecurringLike(amount: (d["amount"] as! NSNumber).int64Value, frequency: d["frequency"] as! String)
}

private func asCashflowInputs(_ any: Any) -> CashflowInputs {
    let d = any as! [String: Any]
    return CashflowInputs(
        monthlyIncome: (d["monthlyIncome"] as! NSNumber).int64Value,
        monthlyPayments: (d["monthlyPayments"] as! NSNumber).int64Value,
        monthlySavings: (d["monthlySavings"] as! NSNumber).int64Value,
        currentSavings: (d["currentSavings"] as! NSNumber).int64Value,
        annualReturnPct: (d["annualReturnPct"] as! NSNumber).doubleValue,
        annualInflationPct: (d["annualInflationPct"] as! NSNumber).doubleValue,
        incomeGrowthPct: (d["incomeGrowthPct"] as? NSNumber)?.doubleValue ?? 0
    )
}

private func yearProjectionToJson(_ p: YearProjection) -> [String: Any] {
    [
        "year": p.year,
        "income": p.income,
        "payments": p.payments,
        "savingsContributed": p.savingsContributed,
        "netCashflow": p.netCashflow,
        "savingsBalance": p.savingsBalance,
        "realSavingsBalance": p.realSavingsBalance,
    ]
}

private func amortRowToJson(_ r: AmortRow) -> [String: Any] {
    [
        "month": r.month,
        "emi": String(r.emi),
        "interest": String(r.interest),
        "principal": String(r.principal),
        "balance": String(r.balance),
    ]
}

private func nullableString(_ any: Any?) -> String? {
    guard let any, !(any is NSNull) else { return nil }
    return any as? String
}

private func nullableInt(_ any: Any?) -> Int? {
    guard let any, !(any is NSNull) else { return nil }
    return (any as? NSNumber)?.intValue
}

func registerFinanceVectors() {
    FunctionRegistry.register(domain: "finance", fn: "futureValue") { input in
        let d = input as! [String: Any]
        let v = try futureValue(
            (d["principal"] as! NSNumber).int64Value,
            (d["contribution"] as! NSNumber).int64Value,
            (d["periodicRate"] as! NSNumber).doubleValue,
            (d["periods"] as! NSNumber).intValue
        )
        return String(v)
    }

    FunctionRegistry.register(domain: "finance", fn: "periodicRateFromAnnual") { input in
        let d = input as! [String: Any]
        return jsonOrNull(periodicRateFromAnnual((d["annualPct"] as! NSNumber).doubleValue, d["period"] as! String))
    }

    FunctionRegistry.register(domain: "finance", fn: "periodsToGoal") { input in
        let d = input as! [String: Any]
        return jsonOrNull(
            periodsToGoal(
                (d["current"] as! NSNumber).int64Value,
                (d["target"] as! NSNumber).int64Value,
                (d["contribution"] as! NSNumber).int64Value,
                (d["periodicRate"] as! NSNumber).doubleValue
            )
        )
    }

    FunctionRegistry.register(domain: "finance", fn: "monthlyEquivalent") { input in
        let d = input as! [String: Any]
        return String(monthlyEquivalent((d["amount"] as! NSNumber).int64Value, d["period"] as! String))
    }

    FunctionRegistry.register(domain: "finance", fn: "recurringMonthlyTotal") { input in
        let d = input as! [String: Any]
        let items = (d["items"] as! [Any]).map(asRecurringLike)
        return String(recurringMonthlyTotal(items))
    }

    FunctionRegistry.register(domain: "finance", fn: "percentOfIncome") { input in
        let d = input as! [String: Any]
        return jsonOrNull(percentOfIncome((d["monthlyAmount"] as! NSNumber).int64Value, (d["monthlyIncome"] as! NSNumber).int64Value))
    }

    FunctionRegistry.register(domain: "finance", fn: "subscriptionImpact") { input in
        let d = input as! [String: Any]
        let r = try subscriptionImpact(
            (d["amount"] as! NSNumber).int64Value,
            d["frequency"] as! String,
            (d["years"] as! NSNumber).doubleValue,
            (d["annualReturnPct"] as! NSNumber).doubleValue
        )
        // NOT stringified -- see file header comment.
        return ["totalPaid": r.totalPaid, "opportunityCost": r.opportunityCost]
    }

    FunctionRegistry.register(domain: "finance", fn: "projectCashflow") { input in
        let d = input as! [String: Any]
        let rows = try projectCashflow(asCashflowInputs(d["inp"]!), (d["years"] as! NSNumber).intValue)
        return rows.map(yearProjectionToJson)
    }

    FunctionRegistry.register(domain: "finance", fn: "yearlyEquivalent") { input in
        let d = input as! [String: Any]
        return String(yearlyEquivalent((d["amount"] as! NSNumber).int64Value, d["period"] as! String))
    }

    FunctionRegistry.register(domain: "finance", fn: "emiFromPrincipal") { input in
        let d = input as! [String: Any]
        return String(
            emiFromPrincipal(
                (d["principal"] as! NSNumber).int64Value,
                (d["annualRatePct"] as! NSNumber).doubleValue,
                (d["tenureMonths"] as! NSNumber).intValue
            )
        )
    }

    FunctionRegistry.register(domain: "finance", fn: "amortizationSchedule") { input in
        let d = input as! [String: Any]
        let rows = amortizationSchedule(
            (d["principal"] as! NSNumber).int64Value,
            (d["annualRatePct"] as! NSNumber).doubleValue,
            (d["emi"] as! NSNumber).int64Value,
            (d["maxMonths"] as! NSNumber).intValue
        )
        return rows.map(amortRowToJson)
    }

    FunctionRegistry.register(domain: "finance", fn: "timeframeTotal") { input in
        let d = input as! [String: Any]
        return String(timeframeTotal((d["monthlyAmount"] as! NSNumber).int64Value, d["timeframe"] as! String))
    }

    FunctionRegistry.register(domain: "finance", fn: "emiDueDate") { input in
        let d = input as! [String: Any]
        let result = emiDueDate(nullableString(d["startIso"]), nullableInt(d["dueDay"]), (d["emiNo"] as! NSNumber).intValue)
        if let result { return result }
        return NSNull()
    }

    FunctionRegistry.register(domain: "finance", fn: "isDuePassed") { input in
        let d = input as! [String: Any]
        return isDuePassed(nullableString(d["dueIso"]), d["asOfIso"] as! String)
    }

    FunctionRegistry.register(domain: "finance", fn: "effectivePaidEmis") { input in
        let d = input as! [String: Any]
        let manual = (d["manual"] as! [Any]).map { ($0 as! NSNumber).intValue }
        let opts = d["opts"] as? [String: Any]
        let result = effectivePaidEmis(
            manual: manual,
            totalEmis: (d["totalEmis"] as! NSNumber).intValue,
            autoMark: (opts?["autoMark"] as? NSNumber)?.boolValue ?? false,
            startIso: nullableString(opts?["startIso"]),
            dueDay: nullableInt(opts?["dueDay"]),
            asOfIso: (opts?["asOfIso"] as? String) ?? "1970-01-01"
        )
        return result.sorted()
    }

    FunctionRegistry.register(domain: "finance", fn: "chargesToDate") { input in
        let d = input as! [String: Any]
        return chargesToDate(nullableString(d["startIso"]), d["period"] as! String, d["asOfIso"] as! String)
    }

    FunctionRegistry.register(domain: "finance", fn: "estimatedSpentToDate") { input in
        let d = input as! [String: Any]
        return String(estimatedSpentToDate(
            (d["amount"] as! NSNumber).int64Value,
            nullableString(d["startIso"]),
            d["period"] as! String,
            d["asOfIso"] as! String
        ))
    }
}
