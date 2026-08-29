import Foundation
@testable import Domain

// Wires Portfolio.swift into FunctionRegistry.
//
// These vectors are the SPECIFICATION, not a recording. All four pieces of
// maths live inside React components on web -- a `useMemo` in
// investments/page.tsx, another in ProjectionPanel.tsx -- and cannot be
// imported into node, which is the same situation dashboard-grid and
// category-tree are in. They were transcribed from those components and then
// pinned here.
//
// Two of the cases exist because they are the ones that would silently differ
// between the platforms rather than fail loudly:
//
//   - `financialYear("2026-03-31")` vs `("2026-04-01")`. Web reads
//     `getMonth() >= 3`, which is APRIL, because JS months are zero-based.
//     Both ports use one-based months, so the boundary had to move by one and
//     an off-by-one here would mis-date every dividend card for a whole month.
//   - `projectPortfolio` with `years = 0`. Web's `for (m = 1; m <= 0; m++)`
//     simply does not run, and Kotlin's `1..0` is likewise empty -- but
//     Swift's `1...0` traps, so the port guards on it and this vector is what
//     keeps that guard honest.

/// Rebuilds an `InvestmentGroup` from the corpus. `holdings` is irrelevant to
/// every function here -- all of them read only the subtotals -- so it is
/// empty rather than a fixture nobody looks at.
private func groupsOf(_ input: [Any]) -> [InvestmentGroup] {
    input.map { entry in
        let g = entry as! [String: Any]
        let cost = (g["cost"] as! NSNumber).int64Value
        let value = (g["value"] as! NSNumber).int64Value
        return InvestmentGroup(
            key: g["key"] as! String,
            label: g["label"] as! String,
            holdings: [],
            cost: cost,
            value: value,
            gain: (g["gain"] as! NSNumber).int64Value,
            gainPct: cost > 0 ? (Double(value - cost) / Double(cost)) * 100.0 : 0
        )
    }
}

func registerPortfolioVectors() {
    FunctionRegistry.register(domain: "investments-portfolio", fn: "allocationSlices") { input in
        let d = input as! [String: Any]
        return allocationSlices(groupsOf(d["groups"] as! [Any])).map {
            ["key": $0.key, "label": $0.label, "valueBase": $0.valueBase, "sharePct": $0.sharePct] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "gainBars") { input in
        let d = input as! [String: Any]
        return gainBars(groupsOf(d["groups"] as! [Any])).map {
            ["key": $0.key, "label": $0.label, "gainBase": $0.gainBase] as [String: Any]
        }
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "fyStart") { input in
        let d = input as! [String: Any]
        return fyStart(d["today"] as! String)
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "financialYear") { input in
        let d = input as! [String: Any]
        let fy = financialYear(d["today"] as! String)
        return ["startYear": fy.startYear, "endYearShort": fy.endYearShort] as [String: Any]
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "inCurrentFyToDate") { input in
        let d = input as! [String: Any]
        return inCurrentFyToDate(d["iso"] as! String, d["today"] as! String)
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "dividendsThisFy") { input in
        let d = input as! [String: Any]
        let events = (d["events"] as! [Any]).map { entry -> DivEvent in
            let e = entry as! [String: Any]
            return DivEvent(
                date: e["date"] as! String,
                base: (e["base"] as! NSNumber).int64Value,
                upcoming: (e["upcoming"] as! NSNumber).boolValue
            )
        }
        return dividendsThisFy(events, d["today"] as! String)
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "dividendYieldRate") { input in
        let d = input as! [String: Any]
        return dividendYieldRate(
            (d["annualDividendBase"] as! NSNumber).int64Value,
            (d["currentValueBase"] as! NSNumber).int64Value
        )
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "projectPortfolio") { input in
        let d = input as! [String: Any]
        let p = projectPortfolio(
            currentValueBase: (d["currentValueBase"] as! NSNumber).int64Value,
            growthPctPerYear: (d["growthPctPerYear"] as! NSNumber).doubleValue,
            monthlyContributionBase: (d["monthlyContributionBase"] as! NSNumber).int64Value,
            years: (d["years"] as! NSNumber).intValue,
            reinvestDividends: (d["reinvestDividends"] as! NSNumber).boolValue,
            dividendYieldRate: (d["dividendYieldRate"] as! NSNumber).doubleValue
        )
        return [
            "points": p.points.map {
                ["yearsOut": $0.yearsOut, "valueBase": $0.valueBase, "contributedBase": $0.contributedBase] as [String: Any]
            },
            "endValueBase": p.endValueBase,
            "contributedBase": p.contributedBase,
            "growthBase": p.growthBase,
        ] as [String: Any]
    }

    FunctionRegistry.register(domain: "investments-portfolio", fn: "clampSipDay") { input in
        let d = input as! [String: Any]
        return clampSipDay((d["day"] as! NSNumber).intValue)
    }
}
