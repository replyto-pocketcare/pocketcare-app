import Foundation
@testable import Domain

// Wires SplitPlan.swift into FunctionRegistry.
//
// A SPEC, not a capture: the rules live in a `useMemo` inside a React component
// and cannot be imported. They were transcribed from
// `apps/web/app/transactions/new/page.tsx` and the transcription was run.
//
// ONE fixture deliberately does NOT match what a browser would produce, and it
// is the JPY one: web's `toMinor` is `Math.round(Number(v) * 100)`, so an
// exact-mode split of a 3000-yen dinner reads every typed share as a hundredth
// of itself, never balances, and the user cannot save at all. This port uses
// `fromMajor(major, currency)`. For INR, USD and EUR the two agree byte for
// byte; the JPY and KWD fixtures are where they part, and they are here so that
// the divergence stays deliberate.
//
// Money travels as STRINGS, per the corpus rule. `percentSum` does not — it is
// a percentage, not an amount. `participants[].value` is the awkward one: it
// carries a percent in percent mode and MINOR UNITS in exact mode, because that
// is the single field `createSplitExpense` takes. It stays a JSON number in
// both, since a field that changes type by mode would be worse than one that
// changes meaning.

func registerSplitPlanVectors() {
    let domain = "split-plan"

    FunctionRegistry.register(domain: domain, fn: "splitPlan") { input in
        let d = input as! [String: Any]
        let plan = splitPlan(
            groupId: d["groupId"] as! String,
            mode: d["mode"] as! String,
            memberIds: (d["memberIds"] as! [Any]).map { $0 as! String },
            me: d["me"] as! String,
            totalMinor: Int64(d["totalMinor"] as! String)!,
            currency: d["currency"] as! String,
            shareText: (d["shareText"] as! [String: Any]).mapValues { $0 as! String },
            multiPayer: (d["multiPayer"] as! NSNumber).boolValue,
            paidText: (d["paidText"] as! [String: Any]).mapValues { $0 as! String },
            hasAccount: (d["hasAccount"] as! NSNumber).boolValue
        )
        return [
            "shares": plan.shares.map { String($0) },
            "sharesSum": String(plan.sharesSum),
            "percentSum": plan.percentSum,
            "paidSum": String(plan.paidSum),
            "valid": plan.valid,
            "participants": plan.participants.map { p -> [String: Any] in
                var out: [String: Any] = ["userId": p.userId]
                // Absent, not null, in equal mode — web builds the object with
                // `value: undefined` there and JSON.stringify drops it.
                if let value = p.value { out["value"] = value }
                return out
            },
            "payers": plan.payers.map { p -> [String: Any] in
                ["userId": p.userId, "paidMinor": String(p.paidMinor), "isMe": p.isMe]
            },
        ] as [String: Any]
    }

    FunctionRegistry.register(domain: domain, fn: "splitActive") { input in
        let d = input as! [String: Any]
        return splitActive(
            type: d["type"] as! String,
            splitOn: (d["splitOn"] as! NSNumber).boolValue,
            groupId: d["groupId"] as! String,
            memberCount: (d["memberCount"] as! NSNumber).intValue
        )
    }

    FunctionRegistry.register(domain: domain, fn: "forOtherActive") { input in
        let d = input as! [String: Any]
        return forOtherActive(
            type: d["type"] as! String,
            splitOn: (d["splitOn"] as! NSNumber).boolValue,
            forOtherOn: (d["forOtherOn"] as! NSNumber).boolValue,
            otherUserId: d["otherUserId"] as! String,
            totalMinor: Int64(d["totalMinor"] as! String)!
        )
    }

    FunctionRegistry.register(domain: domain, fn: "autoSplitGroupFor") { input in
        let d = input as! [String: Any]
        let groups = (d["groups"] as! [Any]).map { row -> AutoSplitCandidate in
            let g = row as! [String: Any]
            return AutoSplitCandidate(
                id: g["id"] as! String,
                startDate: g["startDate"] as? String,
                endDate: g["endDate"] as? String,
                autoSplit: (g["autoSplit"] as? NSNumber)?.boolValue ?? false
            )
        }
        return autoSplitGroupFor(groups: groups, dateIso: d["dateIso"] as! String) ?? NSNull()
    }
}
