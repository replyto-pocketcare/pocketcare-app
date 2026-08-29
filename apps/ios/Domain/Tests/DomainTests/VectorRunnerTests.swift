import Foundation
import XCTest
@testable import Domain

/// P0.4b: loads every golden vector for every domain and reports
/// pass/skip/fail counts per plan section 4. All vectors are skipped
/// until a Phase 1 porting task registers that domain+fn in
/// FunctionRegistry (plan section 5) -- a failure here means a
/// REGISTERED function's output didn't match its vector, never an
/// unregistered (still-skipped) one. One test method per domain file
/// mirrors the Android runner (VectorRunnerTest.kt) 1:1 so CI prints
/// comparable per-domain pass counts for both apps side by side (plan
/// P0.4).
final class VectorRunnerTests: XCTestCase {

    private func runDomain(_ domain: String) throws {
        let vectors = try VectorFixtures.load(domain)
        var passed = 0
        var skipped = 0
        var failures: [String] = []

        for (index, vector) in vectors.enumerated() {
            guard let impl = FunctionRegistry.lookup(domain: domain, fn: vector.fn) else {
                skipped += 1
                continue
            }
            let label = "\(domain)[\(index)] \(vector.fn)"

            if let throwsName = vector.throwsName, let throwsMessage = vector.throwsMessage {
                do {
                    _ = try impl(vector.input)
                    failures.append("\(label): expected throw \(throwsName) but succeeded")
                } catch {
                    // "Error" is JS's generic base class name -- the TS
                    // source throws a plain `new Error(...)` at most call
                    // sites, so there's no single matching Swift error TYPE
                    // to require there (every domain would need its own
                    // "GenericError" stand-in, which isn't worth forcing).
                    // A SPECIFIC name (e.g. "CurrencyMismatchError") means
                    // the TS source threw a deliberately-named subclass, and
                    // that identity is real signal worth checking -- the
                    // Swift port's error type name must match exactly.
                    let actualName = String(describing: type(of: error))
                    let nameOk = throwsName == "Error" || actualName == throwsName
                    let message = String(describing: error)
                    if !nameOk {
                        failures.append("\(label): expected throw type \(throwsName) but got \(actualName)")
                    } else if message != throwsMessage {
                        failures.append("\(label): expected throw message '\(throwsMessage)' but got '\(message)'")
                    } else {
                        passed += 1
                    }
                }
            } else {
                do {
                    let actual = try impl(vector.input)
                    if jsonEqual(actual, vector.expected) {
                        passed += 1
                    } else {
                        failures.append("\(label): expected \(String(describing: vector.expected)) but got \(actual)\n        \(mismatchDetail(expected: vector.expected, actual: actual))")
                    }
                } catch {
                    failures.append("\(label): threw unexpectedly: \(error)")
                }
            }
        }

        print("[vectors] domain=\(domain) total=\(vectors.count) passed=\(passed) skipped=\(skipped) failed=\(failures.count)")
        if !failures.isEmpty {
            XCTFail("\(domain): \(failures.count) vector(s) failed:\n" + failures.joined(separator: "\n"))
        }
    }

    func testBudget() throws {
        // P1.3b: registers Budget.swift's port before running budget.json's
        // vectors, same pattern as testMoney()/testLedger().
        registerBudgetVectors()
        try runDomain("budget")
    }
    func testBudgetSpendSeries() throws {
        // SpendSeries.swift's cumulativeSpendSeries(). Vectors as SPEC --
        // web's version is inlined in a React component that reads the clock.
        registerSpendSeriesVectors()
        try runDomain("budget-spend-series")
    }
    func testGoalCelebration() throws {
        // GoalCelebration.swift's goalCelebration(). Vectors as SPEC again --
        // web's version is a useEffect over a ref and localStorage.
        registerGoalCelebrationVectors()
        try runDomain("goal-celebration")
    }
    func testDiagnostics() throws {
        // P1.6b: registers Diagnostics.swift's port before running
        // diagnostics.json's vectors.
        registerDiagnosticsVectors()
        try runDomain("diagnostics")
    }
    func testEntitlements() throws {
        // P1.7b: registers Entitlements.swift's port before running
        // entitlements.json's vectors.
        registerEntitlementsVectors()
        try runDomain("entitlements")
    }
    func testFinance() throws {
        // P1.3b: registers Finance.swift's port before running finance.json's
        // vectors, same pattern as testMoney()/testLedger().
        registerFinanceVectors()
        try runDomain("finance")
    }
    func testDashboardTrend() throws {
        // Trend.swift's buildTrend()/monthlyCashflow(). Vectors as SPEC again --
        // web's version reads the clock and returns English labels.
        registerTrendVectors()
        try runDomain("dashboard-trend")
    }
    func testWalkthrough() throws {
        // Walkthrough.swift. The full truth table — see WalkthroughVectors.
        registerWalkthroughVectors()
        try runDomain("walkthrough")
    }
    func testCategorize() throws {
        // Categorize.swift + the generated CategorySeeds. Fixtures generated by
        // RUNNING web's own normalize.ts and seeds.ts — see CategorizeVectors.
        registerCategorizeVectors()
        try runDomain("categorize")
    }
    func testAssistant() throws {
        // AssistantMarkdown.swift. Fixtures from running web's own
        // richMessage.tsx — except assistantInlineSpans, which has no capturable
        // value on web; see AssistantVectors.
        registerAssistantVectors()
        try runDomain("assistant")
    }
    func testCardCycle() throws {
        // CardCycle.swift — when a newly-entered credit-card balance is
        // payable. A SPEC, and the fixtures deliberately disagree with a
        // browser about the day: web stores a LOCAL midnight as UTC. See
        // CardCycleVectors.
        registerCardCycleVectors()
        try runDomain("card-cycle")
    }
    func testReceiptsAi() throws {
        // AiReceipt.swift — the AI fallback's reply, mapped into a draft. A
        // SPEC, and the JPY/KWD fixtures deliberately disagree with a browser:
        // web's toMinor is a ×100. See AiReceiptVectors.
        registerAiReceiptVectors()
        try runDomain("receipts-ai")
    }
    func testSplitsRollup() throws {
        // FriendsRollup.swift — who owes whom across the WHOLE ledger, not per
        // group. A SPEC; the fixtures pin the case both ports got wrong, where
        // a balance exists only inside a group. See FriendsRollupVectors.
        registerFriendsRollupVectors()
        try runDomain("splits-rollup")
    }
    func testSplitPlan() throws {
        // SplitPlan.swift — the Add-transaction split editor's arithmetic. A
        // SPEC, and the ONE domain with a fixture that deliberately disagrees
        // with web; see SplitPlanVectors.
        registerSplitPlanVectors()
        try runDomain("split-plan")
    }
    func testSplitsInvite() throws {
        // Invite.swift — who the invite box offers, and what makes two invitees
        // the same person. A SPEC; see InviteVectors.
        registerInviteVectors()
        try runDomain("splits-invite")
    }
    func testFeedback() throws {
        // Feedback.swift — the generated area/severity vocabulary and the key
        // derivation that turns a STORED value into an i18n key.
        registerFeedbackVectors()
        try runDomain("feedback")
    }
    func testAppLink() throws {
        // AppLink.swift — web paths to native destinations. A SPEC, not a
        // capture: web has no such function, only a router. See AppLinkVectors.
        registerAppLinkVectors()
        try runDomain("applink")
    }
    func testStatements() throws {
        // StatementCsv/Analysis/Reconcile.swift. Fixtures generated by RUNNING
        // web's own parseCsv.ts / analysis.ts / reconcile.ts — including two of
        // its defects, see StatementVectors.
        registerStatementVectors()
        try runDomain("statements")
    }
    func testStatementsPdf() throws {
        // StatementPdf.swift. Fixtures generated by RUNNING web's own
        // parsePdf.ts against hand-built row layouts — see StatementPdfVectors.
        registerStatementPdfVectors()
        try runDomain("statements-pdf")
    }
    func testPushState() throws {
        // PushState.swift — the whole cross-product; blocked and off look
        // identical on screen and only one is fixable by tapping.
        registerPushStateVectors()
        try runDomain("push-state")
    }
    func testSplitAssign() throws {
        // SplitAssign.swift — the per-item split screen's own arithmetic,
        // including the sign rule for exactly splitting a discount.
        registerSplitAssignVectors()
        try runDomain("split-assign")
    }
    func testCsv() throws {
        // Csv.swift + ImportAdapters.swift. Generated by running web's REAL
        // csv.ts and adapters.ts — see CsvVectors.swift.
        registerCsvVectors()
        try runDomain("csv")
    }
    func testHelpSearch() throws {
        // HelpSearch.swift. The CONTENT is generated from web
        // (tools/parity/generate-help.mjs); this pins the filter over it.
        registerHelpSearchVectors()
        try runDomain("help-search")
    }
    func testTimeAgo() throws {
        // TimeAgo.swift. Web's version reads the clock inside a page module, so
        // the vectors record a transcription taking `now` as a parameter.
        registerTimeAgoVectors()
        try runDomain("time-ago")
    }
    func testCategoryTree() throws {
        // CategoryTree.swift. Web computes this inside a component's render, so
        // the vectors record a transcription of it — see CategoryTreeVectors.
        registerCategoryTreeVectors()
        try runDomain("category-tree")
    }
    func testSearch() throws {
        // Search.swift's searchTransactions()/activeFilterCount(). Web's filter
        // is inline in a page component, so the vectors record the PORT and
        // three of them pin a deliberate divergence — see SearchVectors.swift.
        registerSearchVectors()
        try runDomain("search")
    }
    func testSplitsCollapse() throws {
        // SplitsCollapse.swift. The collapse half was generated from web's real
        // exported function; the aggregation half was transcribed from a hook.
        registerSplitsCollapseVectors()
        try runDomain("splits-collapse")
    }
    func testSplitsItemBreakdown() throws {
        // ItemBreakdown.swift. Transcribed, not recorded: web's version of this
        // arithmetic lives inside a React component and cannot be run from node.
        registerSplitsItemBreakdownVectors()
        try runDomain("splits-item-breakdown")
    }
    func testInvestmentsPortfolio() throws {
        // Portfolio.swift -- the allocation donut, the gain/loss bars, the
        // financial-year dividend card and the projection curve. A SPEC:
        // every one of them lives inside a React component on web.
        registerPortfolioVectors()
        try runDomain("investments-portfolio")
    }
    func testInstrumentCatalog() throws {
        // InstrumentCatalog.swift -- the Add-investment picker's ranking, and
        // the seed table itself, which is the one thing here transcribed by
        // hand on two platforms and so the one thing that can drift silently.
        registerInstrumentCatalogVectors()
        try runDomain("instrument-catalog")
    }
    func testDashboardGrid() throws {
        // TileGrid.swift's packRows(). Unusually, these vectors are the SPEC:
        // there is no web function to record, because the browser packs the
        // dashboard in CSS.
        registerTileGridVectors()
        try runDomain("dashboard-grid")
    }
    func testRecurringAdvance() throws {
        // Recurring.swift's advance(). The vectors pre-dated the implementation
        // -- re-pinned to clamping 2026-08-23, unenforced until now.
        registerRecurringAdvanceVectors()
        try runDomain("recurring-advance")
    }
    func testGuardrail() throws {
        // P1.6b: registers Guardrail.swift's port before running
        // guardrail.json's vectors.
        registerGuardrailVectors()
        try runDomain("guardrail")
    }
    func testLedger() throws {
        // P1.2b: registers Ledger.swift's port before running ledger.json's
        // vectors, same pattern as testMoney() below.
        registerLedgerVectors()
        try runDomain("ledger")
    }
    func testMoney() throws {
        // P1.1b: registers Money.swift's port before running money.json's
        // vectors. Idempotent (FunctionRegistry.register just overwrites
        // the same key), so this is safe even if XCTest ever re-runs the
        // method. Every other domain here stays fully skipped until its
        // own porting task adds an equivalent call.
        registerMoneyVectors()
        try runDomain("money")
    }
    func testReceiptsAllocate() throws {
        // P1.5b: registers ReceiptsAllocate.swift's port before running
        // receipts-allocate.json's vectors.
        registerReceiptsAllocateVectors()
        try runDomain("receipts-allocate")
    }
    func testReceiptsMoneyText() throws {
        // P1.5b: registers ReceiptsMoneyText.swift's port before running
        // receipts-money-text.json's vectors.
        registerReceiptsMoneyTextVectors()
        try runDomain("receipts-money-text")
    }
    func testReceiptsParse() throws {
        // P1.5b: registers ReceiptsParse.swift's port before running
        // receipts-parse.json's vectors.
        registerReceiptsParseVectors()
        try runDomain("receipts-parse")
    }
    func testReceiptsReconcile() throws {
        // P1.5b: registers ReceiptsReconcile.swift's port before running
        // receipts-reconcile.json's vectors.
        registerReceiptsReconcileVectors()
        try runDomain("receipts-reconcile")
    }
    func testReconcile() throws {
        // P1.6b: registers Reconcile.swift's port before running
        // reconcile.json's vectors.
        registerReconcileVectors()
        try runDomain("reconcile")
    }
    func testSplitsInsights() throws {
        // P1.4b: registers SplitsInsights.swift's port before running
        // splits-insights.json's vectors, same pattern as testMoney()/testLedger().
        registerSplitsInsightsVectors()
        try runDomain("splits-insights")
    }
    func testSplitsMath() throws {
        // P1.4b: registers SplitsMath.swift's port before running
        // splits-math.json's vectors, same pattern as testMoney()/testLedger().
        registerSplitsMathVectors()
        try runDomain("splits-math")
    }
    func testSecurity() throws {
        // Security.swift -- the zero-trust envelope scheme. Unlike every other
        // corpus here, this one was produced by RUNNING web's WebCrypto and
        // capturing its output, because what has to be true is not "the port
        // agrees with itself" but "the port opens a ciphertext a browser
        // wrote". See SecurityVectors.swift.
        registerSecurityVectors()
        try runDomain("security")
    }
    func testSyncPolicy() throws {
        // P1.6b: registers SyncPolicy.swift's port before running
        // sync-policy.json's vectors.
        registerSyncPolicyVectors()
        try runDomain("sync-policy")
    }
    func testUpi() throws {
        // P1.6b: registers Upi.swift's port before running upi.json's vectors.
        registerUpiVectors()
        try runDomain("upi")
    }
    func testSuggestions() throws {
        // Suggestions.swift — the "Worth a look" ranking. The corpus is
        // generated by running web's own @sanvya/suggestions, so the thresholds
        // are pinned to ground truth rather than to a transcription of it.
        registerSuggestionsVectors()
        try runDomain("suggestions")
    }
    func testSyncStatus() throws {
        // SyncNotice.swift — web's syncMessage() minus its English copy. What
        // is pinned is which errors are swallowed as a network wobble.
        registerSyncStatusVectors()
        try runDomain("sync-status")
    }
    func testTransactionAudit() throws {
        // AuditSummary.swift. Web's version is a React component reading a
        // module object literal, so the vectors record a transcription of it —
        // see AuditSummaryVectors for the one divergence they pin.
        registerTransactionAuditVectors()
        try runDomain("transaction-audit")
    }
}


/// Why a comparison failed, in terms a reader can act on.
///
/// The default message renders both sides with `String(describing:)`, which for
/// two doubles that differ in the last bit prints the SAME text twice —
/// `expected Optional(0.006666666666666667) but got 0.006666666666666667` — and
/// tells you nothing. That exact message has now been chased twice. This prints
/// the dynamic type of each side and, for numbers, the raw IEEE-754 bit
/// pattern, so a one-ulp divergence and a genuine type mismatch look different
/// at a glance.
private func mismatchDetail(expected: Any?, actual: Any) -> String {
    func describe(_ value: Any?) -> String {
        guard let value else { return "nil" }
        let type = String(describing: type(of: value))
        if let number = value as? NSNumber {
            let d = number.doubleValue
            return "\(type)(double=\(d), bits=0x\(String(d.bitPattern, radix: 16)), objCType=\(String(cString: number.objCType)))"
        }
        return "\(type)(\(value))"
    }
    return "expected: \(describe(expected)) | actual: \(describe(actual))"
}

/// True only for an NSNumber that's actually CFBoolean-backed (i.e. came
/// from a JSON `true`/`false`, or a Swift Bool bridged to AnyObject) --
/// CFGetTypeID against CFBooleanGetTypeID is the documented, reliable way
/// to tell these apart from a numeric NSNumber that just happens to hold
/// 0/1 (objCType-sniffing is not reliable for this; verified via search
/// before use).
private func isBoolNSNumber(_ n: NSNumber) -> Bool {
    CFGetTypeID(n) == CFBooleanGetTypeID()
}

/// Structural, value-based comparison for two already-unwrapped JSON
/// values (String/NSNumber/NSNull/[Any]/[String: Any] -- exactly what
/// JSONSerialization and our own adapters produce). Recurses into arrays
/// and dictionaries; NSNumbers are compared by actual numeric value (or
/// boolValue, when either side is CFBoolean-backed) rather than via
/// NSNumber.isEqual.
///
/// This replaces an earlier version that bridged straight to
/// `(lhs as AnyObject).isEqual(rhs as AnyObject)` on the assumption that
/// NSNumber's isEqual was reliably value-based -- a real P1.3 test run
/// falsified that assumption: `finance[2] periodicRateFromAnnual:
/// expected Optional(0.006666666666666667) but got 0.006666666666666667`
/// -- textually IDENTICAL values, isEqual still returned false, because
/// the two NSNumbers came from different construction paths (one via
/// `NSNumber(value:)` in the adapter, the other parsed by
/// JSONSerialization) and isEqual is documented to be sensitive to that
/// in some cases (see e.g. isEqualToNumber vs isEqualToValue). Comparing
/// `.doubleValue` directly sidesteps that entirely -- the same fix
/// Vectors.kt's jsonElementsEqual already applied on the Kotlin side for
/// an analogous (if differently-caused) textual-vs-value equality gap.
private func jsonValueEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    switch (lhs, rhs) {
    case (is NSNull, is NSNull):
        return true
    case let (lhsNum as NSNumber, rhsNum as NSNumber):
        let lhsBool = isBoolNSNumber(lhsNum)
        let rhsBool = isBoolNSNumber(rhsNum)
        if lhsBool || rhsBool {
            return lhsBool == rhsBool && lhsNum.boolValue == rhsNum.boolValue
        }
        return lhsNum.doubleValue == rhsNum.doubleValue
    case let (lhsStr as String, rhsStr as String):
        return lhsStr == rhsStr
    case let (lhsArr as [Any], rhsArr as [Any]):
        guard lhsArr.count == rhsArr.count else { return false }
        for i in lhsArr.indices {
            if !jsonValueEqual(lhsArr[i], rhsArr[i]) { return false }
        }
        return true
    case let (lhsDict as [String: Any], rhsDict as [String: Any]):
        guard Set(lhsDict.keys) == Set(rhsDict.keys) else { return false }
        for (key, value) in lhsDict {
            guard let rhsValue = rhsDict[key], jsonValueEqual(value, rhsValue) else { return false }
        }
        return true
    default:
        return false
    }
}

private func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil):
        return true
    case let (lhs?, rhs?):
        return jsonValueEqual(lhs, rhs)
    default:
        return false
    }
}
