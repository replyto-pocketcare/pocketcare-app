package care.pocket.domain.vectors

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
                        if (error.message != vector.throws.message) {
                            failures += "$label: expected throw message '${vector.throws.message}' but got '${error.message}'"
                        } else {
                            passed++
                        }
                    },
                )
            } else {
                result.fold(
                    onSuccess = { actual ->
                        if (actual != vector.expected) {
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

    @Test fun budget() = runDomain("budget")
    @Test fun diagnostics() = runDomain("diagnostics")
    @Test fun entitlements() = runDomain("entitlements")
    @Test fun finance() = runDomain("finance")
    @Test fun guardrail() = runDomain("guardrail")
    @Test fun ledger() = runDomain("ledger")
    @Test fun money() = runDomain("money")
    @Test fun `receipts-allocate`() = runDomain("receipts-allocate")
    @Test fun `receipts-money-text`() = runDomain("receipts-money-text")
    @Test fun `receipts-parse`() = runDomain("receipts-parse")
    @Test fun `receipts-reconcile`() = runDomain("receipts-reconcile")
    @Test fun reconcile() = runDomain("reconcile")
    @Test fun `splits-insights`() = runDomain("splits-insights")
    @Test fun `splits-math`() = runDomain("splits-math")
    @Test fun `sync-policy`() = runDomain("sync-policy")
    @Test fun upi() = runDomain("upi")
}
