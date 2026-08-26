import Foundation
@testable import Domain

// Wires Trend.swift's buildTrend() and monthlyCashflow() into FunctionRegistry.
//
// Like dashboard-grid.json, these vectors have no web function to be recorded
// FROM in a runnable sense -- web's buildTrend reads the clock and returns
// English labels. They pin the ARITHMETIC that survives the port, including the
// one-day overlap in web's four weekly windows, which is preserved on purpose.

func registerTrendVectors() {
    FunctionRegistry.register(domain: "dashboard-trend", fn: "buildTrend") { input in
        let d = input as! [String: Any]
        let daily = (d["dailyTotals"] as! [String: Any]).mapValues { ($0 as! NSNumber).int64Value }
        let buckets = buildTrend(
            daily,
            period: TrendPeriod.from(d["period"] as? String),
            todayIso: d["todayIso"] as! String
        )
        return buckets.map { ["startIso": $0.startIso, "totalMinor": $0.totalMinor] as [String: Any] }
    }

    FunctionRegistry.register(domain: "dashboard-trend", fn: "monthlyCashflow") { input in
        let d = input as! [String: Any]
        let rows = (d["rows"] as! [Any]).map { entry -> (String, String, Int64) in
            let row = entry as! [Any]
            return (row[0] as! String, row[1] as! String, (row[2] as! NSNumber).int64Value)
        }
        let months = monthlyCashflow(rows, months: (d["months"] as! NSNumber).intValue)
        return months.map {
            ["month": $0.month, "incomeMinor": $0.incomeMinor, "expenseMinor": $0.expenseMinor] as [String: Any]
        }
    }
}
