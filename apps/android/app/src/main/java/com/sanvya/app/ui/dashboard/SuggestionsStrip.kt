package com.sanvya.app.ui.dashboard

import android.content.Context
import android.content.SharedPreferences
import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.SuggestionsRepository
import com.sanvya.app.domain.suggestions.SuggestionFeature
import com.sanvya.app.domain.suggestions.UsageCounts
import com.sanvya.app.domain.suggestions.pickSuggestions
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.H2
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.components.initialSyncPending
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import org.json.JSONArray
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

/**
 * Dashboard → "Worth a look" -- a horizontal strip of features this person has
 * not tried yet. A port of `apps/web/src/dashboard/Suggestions.tsx`.
 *
 * WHY IT IS NOT JUST A FEATURE LIST. Most of the app is invisible from the
 * dashboard: someone tracking spends for six months may never learn that loans,
 * budgets or bill-splitting exist. But a permanent "here is what else we sell"
 * rail is an ad, and in a finance app that costs trust. So every rule in
 * `:domain`'s `pickSuggestions` exists to REMOVE cards:
 *
 *  - each suggestion has a prerequisite, so nothing appears until there is
 *    enough history for it to be an observation rather than a pitch,
 *  - credit cards only surface for someone who actually holds one,
 *  - premium features are never suggested to a free user,
 *  - every card is dismissible, permanently,
 *  - and when there is nothing to say the strip renders NOTHING -- no empty
 *    state, no "you have explored everything" badge.
 *
 * **Web's copy is inline English**, with a comment saying the dashboard is not
 * internationalised so one translated widget would look odd. Both native
 * dashboards ARE translated, so the copy is in the `dashboard` namespace here.
 *
 * Mirrors apps/ios/App/Components/SuggestionsStrip.swift.
 */

/**
 * Dismissed features, persisted.
 *
 * Same `localStorage` key web uses (`sanvya:suggestionsDismissed`) and the same
 * JSON-array shape, so the two clients mean one thing by a dismissal. Stored
 * ids are filtered through [SuggestionFeature.fromId] on read: an id from an
 * older build must not sit in the set forever silencing nothing.
 */
object SuggestionsPrefs : KoinComponent {

    private const val PREFS_NAME = "sanvya_prefs"
    private const val DISMISS_KEY = "sanvya:suggestionsDismissed"

    private val context: Context by inject()
    private val sharedPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val _dismissed: MutableStateFlow<Set<String>> by lazy { MutableStateFlow(read()) }
    val dismissed: StateFlow<Set<String>> get() = _dismissed

    private fun read(): Set<String> = runCatching {
        val raw = sharedPrefs.getString(DISMISS_KEY, null) ?: return emptySet()
        val array = JSONArray(raw)
        (0 until array.length())
            .mapNotNull { i -> SuggestionFeature.fromId(array.optString(i))?.id }
            .toSet()
    }.getOrDefault(emptySet())

    fun dismiss(feature: SuggestionFeature) {
        val next = _dismissed.value + feature.id
        val array = JSONArray()
        next.forEach { array.put(it) }
        sharedPrefs.edit().putString(DISMISS_KEY, array.toString()).apply()
        _dismissed.value = next
    }
}

/** What the strip needs to decide whether to draw anything at all. */
data class SuggestionsUiState(
    val usage: UsageCounts = UsageCounts(),
    val dismissed: Set<String> = emptySet(),
    /** Never judge mid-sync -- see [SuggestionsViewModel]. */
    val syncPending: Boolean = true,
    /** The counts have been read at least once. */
    val loaded: Boolean = false,
)

/**
 * The strip's own view model, rather than more fields on `DashboardViewModel`.
 *
 * Web gives this widget its own component with its own query for the same
 * reason: the counts are twelve integers nothing else on the dashboard wants,
 * and folding them into the hero's flow would re-run the net-worth aggregate
 * every time a receipt is saved.
 */
class SuggestionsViewModel : ViewModel(), KoinComponent {
    private val suggestionsRepository: SuggestionsRepository by inject()

    val uiState: StateFlow<SuggestionsUiState> = combine(
        suggestionsRepository.watchUsageCounts(),
        SuggestionsPrefs.dismissed,
        initialSyncPending(),
    ) { usage, dismissed, syncPending ->
        SuggestionsUiState(
            usage = usage,
            dismissed = dismissed,
            syncPending = syncPending,
            loaded = true,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), SuggestionsUiState())
}

/**
 * The strip. Renders nothing -- not an empty state -- when there is nothing to
 * suggest, which is the common case and is meant to be.
 */
@Composable
fun SuggestionsStrip(
    isPaid: Boolean,
    onOpen: (String) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: SuggestionsViewModel = viewModel(),
) {
    val state by viewModel.uiState.collectAsState()

    // Never judge mid-sync. A returning user's rows have not arrived yet, so
    // every count reads zero -- we would tell somebody with five budgets to
    // create their first one. Same reasoning as the first-run walkthrough's
    // own gate, and web says so in the same words.
    if (!state.loaded || state.syncPending) return

    val picked = pickSuggestions(
        usage = state.usage,
        dismissed = state.dismissed,
        isPaid = isPaid,
    )
    if (picked.isEmpty()) return

    val res = sRes()
    val colors = LocalSanvyaColors.current

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            H2(S.Dashboard.suggestTitle(res), modifier = Modifier.weight(1f))
            SanvyaText(
                text = S.Dashboard.suggestSubtitle(res),
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
        }

        // A horizontal rail with the cards bleeding to the screen edge, so a
        // half-visible card signals scrollability instead of stopping dead at
        // the container edge. Web achieves the same with negative margins.
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(horizontal = 16.dp),
        ) {
            items(picked, key = { it.id }) { feature ->
                SuggestionCard(
                    feature = feature,
                    res = res,
                    onOpen = { onOpen(destinationOf(feature)) },
                    onDismiss = { SuggestionsPrefs.dismiss(feature) },
                )
            }
        }
    }
}

@Composable
private fun SuggestionCard(
    feature: SuggestionFeature,
    res: Resources,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val title = titleOf(feature, res)
    SanvyaCard(
        modifier = Modifier.width(CARD_WIDTH),
        padding = PaddingValues(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(SanvyaShape.radiusSm)
                    .background(colors.accentGhost),
                contentAlignment = Alignment.Center,
            ) {
                SanvyaIcon(glyph = iconOf(feature), size = 20.dp, tint = colors.accent)
            }
            Box(modifier = Modifier.weight(1f))
            // "Not interested" has to mean it, so the control that says so is on
            // the card rather than behind a long-press. An icon target rather
            // than a labelled chip: web's is a 13px glyph in the corner, and the
            // words it would need ("Dismiss Track subscriptions") are exactly
            // what a content description is for.
            val dismissLabel = S.Dashboard.suggestDismiss(res, title)
            val interaction = remember { MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .size(24.dp)
                    .clip(SanvyaShape.pill)
                    .background(colors.surface2)
                    .clickable(interactionSource = interaction, indication = null, onClick = onDismiss)
                    .semantics { contentDescription = dismissLabel },
                contentAlignment = Alignment.Center,
            ) {
                SanvyaIcon(glyph = SanvyaIcons.close, size = 13.dp, tint = colors.text2)
            }
        }
        SanvyaText(
            text = title,
            style = SanvyaType.sectionTitle,
            color = colors.text,
            modifier = Modifier.padding(top = 8.dp),
        )
        SanvyaText(
            text = bodyOf(feature, res),
            style = SanvyaType.statLabel,
            color = colors.text2,
            modifier = Modifier.padding(top = 6.dp),
        )
        SanvyaChip(
            label = ctaOf(feature, res),
            active = false,
            onClick = onOpen,
            modifier = Modifier.padding(top = 10.dp),
        )
    }
}

/** Web's `width: min(256px, 78vw)`, as a fixed dp on a phone-first rail. */
private val CARD_WIDTH = 256.dp

/**
 * Where each card's call to action goes.
 *
 * Web's hrefs are `/cashflow#payments` and `/friends`; neither exists as a
 * native route, and the generated tile catalogue already resolved the same two
 * to `recurring` and `splits` -- so this follows TileCatalog rather than
 * inventing a second mapping of the same web paths.
 */
private fun destinationOf(feature: SuggestionFeature): String = when (feature) {
    SuggestionFeature.SUBSCRIPTIONS -> "recurring"
    SuggestionFeature.BUDGETS -> "budgets"
    SuggestionFeature.RECURRING -> "recurring"
    SuggestionFeature.CREDIT_CARDS -> "cards"
    SuggestionFeature.LOANS -> "loans"
    SuggestionFeature.GOALS -> "goals"
    SuggestionFeature.SPLITS -> "splits"
    SuggestionFeature.RECEIPTS -> "receipts/new"
    SuggestionFeature.INVESTMENTS -> "investments"
}

/** Web's per-card MaterialIcon, resolved to this app's icon font. */
private fun iconOf(feature: SuggestionFeature): String = when (feature) {
    SuggestionFeature.SUBSCRIPTIONS -> SanvyaIcons.subscriptions
    SuggestionFeature.BUDGETS -> SanvyaIcons.pieChart
    SuggestionFeature.RECURRING -> SanvyaIcons.autorenew
    SuggestionFeature.CREDIT_CARDS -> SanvyaIcons.creditCard
    SuggestionFeature.LOANS -> SanvyaIcons.requestQuote
    SuggestionFeature.GOALS -> SanvyaIcons.savings
    SuggestionFeature.SPLITS -> SanvyaIcons.groups
    SuggestionFeature.RECEIPTS -> SanvyaIcons.receiptLong
    SuggestionFeature.INVESTMENTS -> SanvyaIcons.trendingUp
}

private fun titleOf(feature: SuggestionFeature, res: Resources): String = when (feature) {
    SuggestionFeature.SUBSCRIPTIONS -> S.Dashboard.suggestSubscriptionsTitle(res)
    SuggestionFeature.BUDGETS -> S.Dashboard.suggestBudgetsTitle(res)
    SuggestionFeature.RECURRING -> S.Dashboard.suggestRecurringTitle(res)
    SuggestionFeature.CREDIT_CARDS -> S.Dashboard.suggestCreditCardsTitle(res)
    SuggestionFeature.LOANS -> S.Dashboard.suggestLoansTitle(res)
    SuggestionFeature.GOALS -> S.Dashboard.suggestGoalsTitle(res)
    SuggestionFeature.SPLITS -> S.Dashboard.suggestSplitsTitle(res)
    SuggestionFeature.RECEIPTS -> S.Dashboard.suggestReceiptsTitle(res)
    SuggestionFeature.INVESTMENTS -> S.Dashboard.suggestInvestmentsTitle(res)
}

private fun bodyOf(feature: SuggestionFeature, res: Resources): String = when (feature) {
    SuggestionFeature.SUBSCRIPTIONS -> S.Dashboard.suggestSubscriptionsBody(res)
    SuggestionFeature.BUDGETS -> S.Dashboard.suggestBudgetsBody(res)
    SuggestionFeature.RECURRING -> S.Dashboard.suggestRecurringBody(res)
    SuggestionFeature.CREDIT_CARDS -> S.Dashboard.suggestCreditCardsBody(res)
    SuggestionFeature.LOANS -> S.Dashboard.suggestLoansBody(res)
    SuggestionFeature.GOALS -> S.Dashboard.suggestGoalsBody(res)
    SuggestionFeature.SPLITS -> S.Dashboard.suggestSplitsBody(res)
    SuggestionFeature.RECEIPTS -> S.Dashboard.suggestReceiptsBody(res)
    SuggestionFeature.INVESTMENTS -> S.Dashboard.suggestInvestmentsBody(res)
}

private fun ctaOf(feature: SuggestionFeature, res: Resources): String = when (feature) {
    SuggestionFeature.SUBSCRIPTIONS -> S.Dashboard.suggestSubscriptionsCta(res)
    SuggestionFeature.BUDGETS -> S.Dashboard.suggestBudgetsCta(res)
    SuggestionFeature.RECURRING -> S.Dashboard.suggestRecurringCta(res)
    SuggestionFeature.CREDIT_CARDS -> S.Dashboard.suggestCreditCardsCta(res)
    SuggestionFeature.LOANS -> S.Dashboard.suggestLoansCta(res)
    SuggestionFeature.GOALS -> S.Dashboard.suggestGoalsCta(res)
    SuggestionFeature.SPLITS -> S.Dashboard.suggestSplitsCta(res)
    SuggestionFeature.RECEIPTS -> S.Dashboard.suggestReceiptsCta(res)
    SuggestionFeature.INVESTMENTS -> S.Dashboard.suggestInvestmentsCta(res)
}
