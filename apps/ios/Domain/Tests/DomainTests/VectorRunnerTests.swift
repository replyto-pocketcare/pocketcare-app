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
                        failures.append("\(label): expected \(String(describing: vector.expected)) but got \(actual)")
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
    func testDiagnostics() throws { try runDomain("diagnostics") }
    func testEntitlements() throws { try runDomain("entitlements") }
    func testFinance() throws {
        // P1.3b: registers Finance.swift's port before running finance.json's
        // vectors, same pattern as testMoney()/testLedger().
        registerFinanceVectors()
        try runDomain("finance")
    }
    func testGuardrail() throws { try runDomain("guardrail") }
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
    func testReceiptsAllocate() throws { try runDomain("receipts-allocate") }
    func testReceiptsMoneyText() throws { try runDomain("receipts-money-text") }
    func testReceiptsParse() throws { try runDomain("receipts-parse") }
    func testReceiptsReconcile() throws { try runDomain("receipts-reconcile") }
    func testReconcile() throws { try runDomain("reconcile") }
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
    func testSyncPolicy() throws { try runDomain("sync-policy") }
    func testUpi() throws { try runDomain("upi") }
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
