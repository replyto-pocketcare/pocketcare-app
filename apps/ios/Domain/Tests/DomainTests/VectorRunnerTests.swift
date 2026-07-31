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

    func testBudget() throws { try runDomain("budget") }
    func testDiagnostics() throws { try runDomain("diagnostics") }
    func testEntitlements() throws { try runDomain("entitlements") }
    func testFinance() throws { try runDomain("finance") }
    func testGuardrail() throws { try runDomain("guardrail") }
    func testLedger() throws { try runDomain("ledger") }
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
    func testSplitsInsights() throws { try runDomain("splits-insights") }
    func testSplitsMath() throws { try runDomain("splits-math") }
    func testSyncPolicy() throws { try runDomain("sync-policy") }
    func testUpi() throws { try runDomain("upi") }
}

/// Foundation's JSONSerialization output is NSNumber/NSString/NSArray/
/// NSDictionary/NSNull -- all of which implement deep structural
/// `isEqual` -- so bridging to AnyObject gets a correct recursive
/// comparison for free instead of hand-writing one.
private func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil):
        return true
    case let (lhs?, rhs?):
        return (lhs as AnyObject).isEqual(rhs as AnyObject)
    default:
        return false
    }
}
