package com.sanvya.app.domain.vectors

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
        com.sanvya.app.domain.budget.registerBudgetVectors()
        runDomain("budget")
    }
    @Test
    fun diagnostics() {
        // P1.6a: registers Diagnostics.kt's port before running
        // diagnostics.json's vectors.
        com.sanvya.app.domain.diagnostics.registerDiagnosticsVectors()
        runDomain("diagnostics")
    }
    @Test
    fun entitlements() {
        // P1.7a: registers Entitlements.kt's port before running
        // entitlements.json's vectors.
        com.sanvya.app.domain.entitlements.registerEntitlementsVectors()
        runDomain("entitlements")
    }
    @Test
    fun finance() {
        // P1.3a: registers Finance.kt's port before running finance.json's
        // vectors, same pattern as money()/ledger().
        com.sanvya.app.domain.finance.registerFinanceVectors()
        runDomain("finance")
    }
    @Test
    fun `dashboard-trend`() {
        // Trend.kt's buildTrend()/monthlyCashflow(). Vectors as SPEC again --
        // web's version reads the clock and returns English labels.
        com.sanvya.app.domain.dashboard.registerTrendVectors()
        runDomain("dashboard-trend")
    }
    @Test
    fun walkthrough() {
        // Walkthrough.kt. The full truth table -- see WalkthroughVectors.kt.
        com.sanvya.app.domain.onboarding.registerWalkthroughVectors()
        runDomain("walkthrough")
    }
    @Test
    fun categorize() {
        // Categorize.kt + the generated CategorySeeds. Fixtures generated by
        // RUNNING web's own normalize.ts and seeds.ts -- see CategorizeVectors.kt.
        com.sanvya.app.domain.categorize.registerCategorizeVectors()
        runDomain("categorize")
    }
    @Test
    fun assistant() {
        // AssistantMarkdown.kt. Fixtures from running web's own richMessage.tsx
        // -- except assistantInlineSpans, which has no capturable value on web;
        // see AssistantVectors.kt.
        com.sanvya.app.domain.assistant.registerAssistantVectors()
        runDomain("assistant")
    }
    @Test
    fun feedback() {
        // Feedback.kt -- the generated area/severity vocabulary and the key
        // derivation that turns a STORED value into an i18n key.
        com.sanvya.app.domain.feedback.registerFeedbackVectors()
        runDomain("feedback")
    }
    @Test
    fun applink() {
        // AppLink.kt -- web paths to native destinations. A SPEC, not a
        // capture: web has no such function, only a router. See AppLinkVectors.kt.
        com.sanvya.app.domain.navigation.registerAppLinkVectors()
        runDomain("applink")
    }
    @Test
    fun statements() {
        // StatementCsv/Analysis/Reconcile.kt. Fixtures generated by RUNNING
        // web's own parseCsv.ts / analysis.ts / reconcile.ts -- including two of
        // its defects, see StatementVectors.kt.
        com.sanvya.app.domain.statements.registerStatementVectors()
        runDomain("statements")
    }
    @Test
    fun `statements-pdf`() {
        // StatementPdf.kt. Fixtures generated by RUNNING web's own parsePdf.ts
        // against hand-built row layouts -- see StatementPdfVectors.kt.
        com.sanvya.app.domain.statements.registerStatementPdfVectors()
        runDomain("statements-pdf")
    }
    @Test
    fun pushState() {
        // PushState.kt -- the whole cross-product; BLOCKED and OFF look
        // identical on screen and only one is fixable by tapping.
        com.sanvya.app.domain.notifications.registerPushStateVectors()
        runDomain("push-state")
    }
    @Test
    fun splitAssign() {
        // SplitAssign.kt -- the per-item split screen's own arithmetic,
        // including the sign rule for exactly splitting a discount.
        com.sanvya.app.domain.receipts.registerSplitAssignVectors()
        runDomain("split-assign")
    }
    @Test
    fun csv() {
        // Csv.kt + ImportAdapters.kt. Generated by running web's REAL csv.ts
        // and adapters.ts -- see CsvVectors.kt.
        com.sanvya.app.domain.csv.registerCsvVectors()
        runDomain("csv")
    }
    @Test
    fun `help-search`() {
        // HelpSearch.kt. The CONTENT is generated from web
        // (tools/parity/generate-help.mjs); this pins the filter over it.
        com.sanvya.app.domain.help.registerHelpSearchVectors()
        runDomain("help-search")
    }
    @Test
    fun `time-ago`() {
        // TimeAgo.kt. Web's version reads the clock inside a page module, so the
        // vectors record a transcription taking `now` as a parameter.
        com.sanvya.app.domain.notifications.registerTimeAgoVectors()
        runDomain("time-ago")
    }
    @Test
    fun `category-tree`() {
        // CategoryTree.kt. Web computes this inside a component's render, so the
        // vectors record a transcription of it -- see CategoryTreeVectors.kt.
        com.sanvya.app.domain.taxonomy.registerCategoryTreeVectors()
        runDomain("category-tree")
    }
    @Test
    fun search() {
        // Search.kt's searchTransactions()/activeFilterCount(). Web's filter is
        // inline in a page component, so the vectors record the PORT and three
        // of them pin a deliberate divergence -- see SearchVectors.kt.
        com.sanvya.app.domain.search.registerSearchVectors()
        runDomain("search")
    }
    @Test
    fun `splits-collapse`() {
        // Collapse.kt. The collapse half was generated from web's real exported
        // function; the aggregation half was transcribed from a hook.
        com.sanvya.app.domain.splits.registerSplitsCollapseVectors()
        runDomain("splits-collapse")
    }
    @Test
    fun `dashboard-grid`() {
        // TileGrid.kt's packRows(). Unusually, these vectors are the SPEC:
        // there is no web function to record, because the browser packs the
        // dashboard in CSS.
        com.sanvya.app.domain.dashboard.registerTileGridVectors()
        runDomain("dashboard-grid")
    }
    @Test
    fun `recurring-advance`() {
        // Recurring.kt's advance(). The vectors pre-dated the implementation --
        // re-pinned to clamping 2026-08-23, unenforced until now.
        com.sanvya.app.domain.recurring.registerRecurringAdvanceVectors()
        runDomain("recurring-advance")
    }
    @Test
    fun guardrail() {
        // P1.6a: registers Guardrail.kt's port before running
        // guardrail.json's vectors.
        com.sanvya.app.domain.guardrail.registerGuardrailVectors()
        runDomain("guardrail")
    }
    @Test
    fun ledger() {
        // P1.2a: registers Ledger.kt's port before running ledger.json's
        // vectors, same pattern as money() below.
        com.sanvya.app.domain.ledger.registerLedgerVectors()
        runDomain("ledger")
    }
    @Test
    fun money() {
        // P1.1a: registers Money.kt's port before running money.json's
        // vectors. Idempotent (FunctionRegistry.register just overwrites
        // the same key), so this is safe even if JUnit ever re-runs the
        // method. Every other domain here stays fully skipped until its
        // own porting task adds an equivalent call.
        com.sanvya.app.domain.money.registerMoneyVectors()
        runDomain("money")
    }
    @Test
    fun `receipts-allocate`() {
        // P1.5a: registers ReceiptsAllocate.kt's port before running
        // receipts-allocate.json's vectors, same pattern as money()/ledger().
        com.sanvya.app.domain.receipts.registerReceiptsAllocateVectors()
        runDomain("receipts-allocate")
    }
    @Test
    fun `receipts-money-text`() {
        // P1.5a: registers ReceiptsMoneyText.kt's port before running
        // receipts-money-text.json's vectors.
        com.sanvya.app.domain.receipts.registerReceiptsMoneyTextVectors()
        runDomain("receipts-money-text")
    }
    @Test
    fun `receipts-parse`() {
        // P1.5a: registers ReceiptsParse.kt's port before running
        // receipts-parse.json's vectors.
        com.sanvya.app.domain.receipts.registerReceiptsParseVectors()
        runDomain("receipts-parse")
    }
    @Test
    fun `receipts-reconcile`() {
        // P1.5a: registers ReceiptsReconcile.kt's port before running
        // receipts-reconcile.json's vectors.
        com.sanvya.app.domain.receipts.registerReceiptsReconcileVectors()
        runDomain("receipts-reconcile")
    }
    @Test
    fun reconcile() {
        // P1.6a: registers Reconcile.kt's port before running reconcile.json's
        // vectors, same pattern as money()/ledger().
        com.sanvya.app.domain.reconcile.registerReconcileVectors()
        runDomain("reconcile")
    }
    @Test
    fun `splits-insights`() {
        // P1.4a: registers SplitsInsights.kt's port before running
        // splits-insights.json's vectors, same pattern as money()/ledger().
        com.sanvya.app.domain.splitsinsights.registerSplitsInsightsVectors()
        runDomain("splits-insights")
    }
    @Test
    fun `splits-math`() {
        // P1.4a: registers SplitsMath.kt's port before running
        // splits-math.json's vectors, same pattern as money()/ledger().
        com.sanvya.app.domain.splitsmath.registerSplitsMathVectors()
        runDomain("splits-math")
    }
    @Test
    fun `sync-policy`() {
        // P1.6a: registers SyncPolicy.kt's port before running
        // sync-policy.json's vectors.
        com.sanvya.app.domain.syncpolicy.registerSyncPolicyVectors()
        runDomain("sync-policy")
    }
    @Test
    fun upi() {
        // P1.6a: registers Upi.kt's port before running upi.json's vectors.
        com.sanvya.app.domain.upi.registerUpiVectors()
        runDomain("upi")
    }
}
