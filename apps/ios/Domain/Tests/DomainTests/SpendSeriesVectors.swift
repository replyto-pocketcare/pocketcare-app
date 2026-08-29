import Foundation
@testable import Domain

// Wires SpendSeries.swift's cumulativeSpendSeries() into FunctionRegistry.
//
// Like dashboard-grid.json and dashboard-trend.json, these vectors have no web
// function to be recorded FROM in a runnable sense -- web's version is inlined
// in a React component, reads the clock and returns localised day labels. They
// pin the ARITHMETIC that survives the port: the clamp to today, the 92-day
// step threshold, the always-sampled last day, and the `max(1, ...)` floor that
// makes a not-yet-started window come back empty rather than looping backwards.
//
// Minor-unit amounts are plain JSON numbers here rather than the decimal
// STRINGS export.ts writes for `Money` values, matching dashboard-trend.json --
// this corpus is hand-authored in the same family and its inputs are a
// day-to-total map, not a Money.

func registerSpendSeriesVectors() {
    FunctionRegistry.register(domain: "budget-spend-series", fn: "cumulativeSpendSeries") { input in
        let d = input as! [String: Any]
        let daily = (d["dailyTotals"] as! [String: Any]).mapValues { ($0 as! NSNumber).int64Value }
        let points = cumulativeSpendSeries(
            daily,
            startIso: d["startIso"] as! String,
            endIso: d["endIso"] as! String,
            todayIso: d["todayIso"] as! String
        )
        return points.map { ["dayIso": $0.dayIso, "cumulativeMinor": $0.cumulativeMinor] as [String: Any] }
    }
}
