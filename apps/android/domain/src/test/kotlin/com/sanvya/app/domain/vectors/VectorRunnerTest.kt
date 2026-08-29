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
    fun `budget-spend-series`() {
        // SpendSeries.kt's cumulativeSpendSeries(). Vectors as SPEC -- web's
        // version is inlined in a React component that reads the clock.
        com.sanvya.app.domain.budget.registerSpendSeriesVectors()
        runDomain("budget-spend-series")
    }
    @Test
    fun `goal-celebration`() {
        // Celebration.kt's goalCelebration(). Vectors as SPEC again -- web's
        // version is a useEffect over a ref and localStorage.
        com.sanvya.app.domain.goals.registerCelebrationVectors()
        runDomain("goal-celebration")
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
    fun `split-plan`() {
        // SplitPlan.kt -- the Add-transaction split editor's arithmetic. A SPEC,
        // and the ONE domain with a fixture that deliberately disagrees with
        // web; see SplitPlanVectors.kt.
        com.sanvya.app.domain.splits.registerSplitPlanVectors()
        runDomain("split-plan")
    }
    @Test
    fun `splits-invite`() {
        // Invite.kt -- who the invite box offers, and what makes two invitees
        // the same person. A SPEC; see InviteVectors.kt.
        com.sanvya.app.domain.splits.registerInviteVectors()
        runDomain("splits-invite")
    }
    @Test
    fun feedback() {
        // Feedback.kt -- the generated area/severity vocabulary and the key
        // derivation that turns a STORED value into an i18n key.
        com.sanvya.app.domain.feedback.registerFeedbackVectors()
        runDomain("feedback")
    }
    @Test
    fun `card-cycle`() {
        // CardCycle.kt -- when a newly-entered credit-card balance is payable.
        // A SPEC, and the fixtures deliberately disagree with a browser about
        // the day: web stores a LOCAL midnight as UTC. See CardCycleVectors.kt.
        com.sanvya.app.domain.cards.registerCardCycleVectors()
        runDomain("card-cycle")
    }
    @Test
    fun `receipts-ai`() {
        // AiReceipt.kt -- the AI fallback's reply, mapped into a draft. A SPEC,
        // and the JPY/KWD fixtures deliberately disagree with a browser: web's
        // toMinor is a x100. See AiReceiptVectors.kt.
        com.sanvya.app.domain.receipts.registerAiReceiptVectors()
        runDomain("receipts-ai")
    }
    @Test
    fun `splits-rollup`() {
        // FriendsRollup.kt -- who owes whom across the WHOLE ledger, not per
        // group. A SPEC; the fixtures pin the case both ports got wrong, where
        // a balance exists only inside a group. See FriendsRollupVectors.kt.
        com.sanvya.app.domain.splits.registerFriendsRollupVectors()
        runDomain("splits-rollup")
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
    fun `splits-item-breakdown`() {
        // ItemBreakdown.kt. Transcribed, not recorded: web's version of this
        // arithmetic lives inside a React component and cannot be run from node.
        com.sanvya.app.domain.splits.registerSplitsItemBreakdownVectors()
        runDomain("splits-item-breakdown")
    }
    @Test
    fun `investments-portfolio`() {
        // Portfolio.kt -- the allocation donut, the gain/loss bars, the
        // financial-year dividend card and the projection curve. A SPEC:
        // every one of them lives inside a React component on web.
        com.sanvya.app.domain.investments.registerPortfolioVectors()
        runDomain("investments-portfolio")
    }
    @Test
    fun `instrument-catalog`() {
        // InstrumentCatalog.kt -- the Add-investment picker's ranking, and the
        // seed table itself, which is the one thing here transcribed by hand
        // on two platforms and so the one thing that can drift silently.
        com.sanvya.app.domain.investments.registerInstrumentCatalogVectors()
        runDomain("instrument-catalog")
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
    @Test
    fun suggestions() {
        // Suggestions.kt -- the "Worth a look" ranking. The corpus is generated
        // by running web's own @sanvya/suggestions, so the thresholds are
        // pinned to ground truth rather than to a transcription of it.
        com.sanvya.app.domain.suggestions.registerSuggestionsVectors()
        runDomain("suggestions")
    }
    @Test
    fun `sync-status`() {
        // SyncNotice.kt -- web's syncMessage() minus its English copy. What is
        // pinned is which errors are swallowed as a network wobble.
        com.sanvya.app.domain.syncstatus.registerSyncStatusVectors()
        runDomain("sync-status")
    }
    @Test
    fun `transaction-audit`() {
        // AuditSummary.kt. Web's version is a React component reading a module
        // object literal, so the vectors record a transcription of it -- see
        // AuditSummaryVectors.kt for the one divergence they pin.
        com.sanvya.app.domain.transactions.registerTransactionAuditVectors()
        runDomain("transaction-audit")
    }
}
