package care.pocket.domain.vectors

import kotlinx.serialization.json.JsonNull
import kotlin.test.Test
import kotlin.test.fail

/**
 * P0.4a: loads every golden vector for every domain and reports
 * pass/skip/fail counts per plan §4. All vectors are skipped until a
 * Phase 1 porting task registers that domain+fn in FunctionRegistry (plan
 * §5) — a failure here means a REGISTERED function's output didn't match
 * its vector, never an unregistered (still-skipped) one. One @Test per
 * domain file mirrors the files under tools/golden-vectors/vectors 1:1,
 * so CI's per-test pass/fail lines double as the "per-domain pass counts"
 * plan §4/P0.4 asks for.
 */
class VectorRunnerTest {

    private fun runDomain(domain: String) {
        val vectors = loadVectors(domain)
        var passed = 0
        var skipped = 0
        val failures = mutableListOf<String>()

        vectors.forEachIndexed { index, vector ->
            val impl = FunctionRegistry.lookup(domain, vector.fn)
            if (impl == null) {
                skipped++
                return@forEachIndexed
            }
            val label = "$domain[$index] ${vector.fn}(${vector.input})"
            val result = runCatching { impl(vector.input) }

            if (vector.throws != null) {
                result.fold(
                    onSuccess = {
                        failures += "$label: expected throw ${vector.throws.name} but succeeded"
                    },
                    onFailure = { error ->
                        // "Error" is JS's generic base class name -- the TS
                        // source throws a plain `new Error(...)` at most call
                        // sites, so there's no single matching Kotlin
                        // exception TYPE to require there (forcing every
                        // generic-error site to be literally named "Error"
                        // would be unidiomatic). A SPECIFIC name (e.g.
                        // "CurrencyMismatchError") means the TS source threw
                        // a deliberately-named subclass, and that identity is
                        // real signal worth checking -- the Kotlin port's
                        // exception class name must match exactly.
                        val nameOk = vector.throws.name == "Error" ||
                            error::class.simpleName == vector.throws.name
                        when {
                            !nameOk -> failures += "$label: expected throw type ${vector.throws.name} but got ${error::class.simpleName}"
                            error.message != vector.throws.message -> failures += "$label: expected throw message '${vector.throws.message}' but got '${error.message}'"
                            else -> passed++
                        }
                    },
                )
            } else {
                result.fold(
                    onSuccess = { actual ->
                        // jsonElementsEqual, not raw !=: JsonElement's default
                        // equality compares numeric JsonPrimitives by their
                        // literal string content, which only accidentally
                        // matches V8's own Double formatting -- see its
                        // doc comment in Vectors.kt (added for P1.3, finance,
                        // the first domain with genuinely fractional
                        // non-money doubles like periodicRateFromAnnual).
                        if (!jsonElementsEqual(actual, vector.expected ?: JsonNull)) {
                            failures += "$label: expected ${vector.expected} but got $actual"
                        } else {
                            passed++
                        }
                    },
                    onFailure = { error ->
                        failures += "$label: threw unexpectedly: $error"
                    },
                )
            }
        }

        println(
            "[vectors] domain=$domain total=${vectors.size} passed=$passed " +
                "skipped=$skipped failed=${failures.size}"
        )
        if (failures.isNotEmpty()) {
            fail("$domain: ${failures.size} vector(s) failed:\n" + failures.joinToString("\n"))
        }
    }

    @Test
    fun budget() {
        // P1.3a: registers Budget.kt's port before running budget.json's
        // vectors, same pattern as money()/ledger().
        care.pocket.domain.budget.registerBudgetVectors()
        runDomain("budget")
    }
    @Test fun diagnostics() = runDomain("diagnostics")
    @Test fun entitlements() = runDomain("entitlements")
    @Test
    fun finance() {
        // P1.3a: registers Finance.kt's port before running finance.json's
        // vectors, same pattern as money()/ledger().
        care.pocket.domain.finance.registerFinanceVectors()
        runDomain("finance")
    }
    @Test fun guardrail() = runDomain("guardrail")
    @Test
    fun ledger() {
        // P1.2a: registers Ledger.kt's port before running ledger.json's
        // vectors, same pattern as money() below.
        care.pocket.domain.ledger.registerLedgerVectors()
        runDomain("ledger")
    }
    @Test
    fun money() {
        // P1.1a: registers Money.kt's port before running money.json's
        // vectors. Idempotent (FunctionRegistry.register just overwrites
        // the same key), so this is safe even if JUnit ever re-runs the
        // method. Every other domain here stays fully skipped until its
        // own porting task adds an equivalent call.
        care.pocket.domain.money.registerMoneyVectors()
        runDomain("money")
    }
    @Test
    fun `receipts-allocate`() {
        // P1.5a: registers ReceiptsAllocate.kt's port before running
        // receipts-allocate.json's vectors, same pattern as money()/ledger().
        care.pocket.domain.receipts.registerReceiptsAllocateVectors()
        runDomain("receipts-allocate")
    }
    @Test
    fun `receipts-money-text`() {
        // P1.5a: registers ReceiptsMoneyText.kt's port before running
        // receipts-money-text.json's vectors.
        care.pocket.domain.receipts.registerReceiptsMoneyTextVectors()
        runDomain("receipts-money-text")
    }
    @Test
    fun `receipts-parse`() {
        // P1.5a: registers ReceiptsParse.kt's port before running
        // receipts-parse.json's vectors.
        care.pocket.domain.receipts.registerReceiptsParseVectors()
        runDomain("receipts-parse")
    }
    @Test
    fun `receipts-reconcile`() {
        // P1.5a: registers ReceiptsReconcile.kt's port before running
        // receipts-reconcile.json's vectors.
        care.pocket.domain.receipts.registerReceiptsReconcileVectors()
        runDomain("receipts-reconcile")
    }
    @Test fun reconcile() = runDomain("reconcile")
    @Test
    fun `splits-insights`() {
        // P1.4a: registers SplitsInsights.kt's port before running
        // splits-insights.json's vectors, same pattern as money()/ledger().
        care.pocket.domain.splitsinsights.registerSplitsInsightsVectors()
        runDomain("splits-insights")
    }
    @Test
    fun `splits-math`() {
        // P1.4a: registers SplitsMath.kt's port before running
        // splits-math.json's vectors, same pattern as money()/ledger().
        care.pocket.domain.splitsmath.registerSplitsMathVectors()
        runDomain("splits-math")
    }
    @Test fun `sync-policy`() = runDomain("sync-policy")
    @Test fun upi() = runDomain("upi")
}
