package com.sanvya.app.ui.dashboard

import android.content.res.Resources
import android.provider.Settings
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * The wide-window KPI strip -- four headline figures across the top of the
 * dashboard, each with a period-over-period delta. A port of
 * `apps/web/src/ui/desktop/StatRow.tsx`.
 *
 * **Only at EXPANDED, and this is not an optimisation.** On a phone the strip
 * would repeat the net-worth hero directly beneath it in a smaller font; web
 * mounts it behind `useIsDesktop()` for the same reason and says so. The gate
 * here is `SanvyaWindowClass.EXPANDED` rather than a pixel width, because that
 * is the app's existing answer to "is there room for a second layout" and web's
 * 1024px CSS breakpoint is not a number an Android device is measured in.
 *
 * All four figures are MINOR units all the way to `formatMoney`; the count-up
 * animates the minor integer and rounds back to a Long before formatting, so a
 * zero-decimal currency never gains a fractional step mid-tween.
 *
 * Mirrors apps/ios/App/Components/StatRow.swift.
 */
@Composable
fun StatRow(stats: DashboardStats, hidden: Boolean, modifier: Modifier = Modifier) {
    val res = sRes()
    val colors = LocalSanvyaColors.current

    val currentNet = stats.currentIncomeMinor - stats.currentExpenseMinor
    val previousNet = stats.previousIncomeMinor - stats.previousExpenseMinor

    val cards = listOf(
        // Net worth has no meaningful stored "last month" figure, so it compares
        // against itself minus this month's movement -- i.e. where it started.
        StatCardData(
            label = S.Dashboard.statNetWorth(res),
            glyph = SanvyaIcons.accountBalance,
            tint = colors.forest,
            minor = stats.netMinor,
            previousMinor = stats.netMinor - currentNet,
        ),
        StatCardData(
            label = S.Dashboard.statIncome(res),
            glyph = SanvyaIcons.trendingUp,
            tint = colors.positive,
            minor = stats.currentIncomeMinor,
            previousMinor = stats.previousIncomeMinor,
        ),
        StatCardData(
            label = S.Dashboard.statSpending(res),
            glyph = SanvyaIcons.payments,
            tint = colors.negative,
            minor = stats.currentExpenseMinor,
            previousMinor = stats.previousExpenseMinor,
            // "Good" is not the same as "up": more spending is a worse month, so
            // the pill's colour follows the meaning while the arrow follows the
            // direction.
            inverse = true,
        ),
        StatCardData(
            label = S.Dashboard.statSaved(res),
            glyph = SanvyaIcons.savings,
            tint = colors.teal,
            minor = currentNet,
            previousMinor = previousNet,
        ),
    )

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        cards.forEach { card ->
            StatCard(card = card, base = stats.base, hidden = hidden, res = res)
        }
    }
}

private data class StatCardData(
    val label: String,
    val glyph: String,
    val tint: Color,
    /** Current-period figure, in MINOR units. */
    val minor: Long,
    /** Previous-period figure, in MINOR units -- drives the delta pill. */
    val previousMinor: Long,
    /** When true a RISE is bad (spending). Flips the pill's colour only. */
    val inverse: Boolean = false,
)

@Composable
private fun RowScope.StatCard(
    card: StatCardData,
    base: String,
    hidden: Boolean,
    res: Resources,
) {
    val colors = LocalSanvyaColors.current
    val shown = countUp(card.minor, enabled = !hidden)

    // Null when there is nothing to divide by: a first month has no percentage,
    // and "+100%" against zero is a lie dressed as a fact.
    val percent = if (card.previousMinor == 0L) {
        null
    } else {
        ((card.minor - card.previousMinor).toDouble() / abs(card.previousMinor).toDouble()) * 100.0
    }
    val rose = (percent ?: 0.0) >= 0.0
    val good = if (card.inverse) !rose else rose

    SanvyaCard(modifier = Modifier.weight(1f), padding = PaddingValues(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaText(
                text = card.label,
                style = SanvyaType.statLabel,
                color = colors.text2,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Box(
                modifier = Modifier
                    .size(26.dp)
                    .clip(SanvyaShape.radiusSm)
                    // Web tints the chip with `color-mix(... 16%, transparent)`.
                    // A 16% alpha of the same colour over the card is the same
                    // result without a colour-space function Compose lacks.
                    .background(card.tint.copy(alpha = 0.16f)),
                contentAlignment = Alignment.Center,
            ) {
                SanvyaIcon(glyph = card.glyph, size = 16.dp, tint = card.tint)
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaText(
                text = if (hidden) HIDDEN_AMOUNT else formatMoney(shown, base),
                style = SanvyaType.statValue,
                color = colors.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (percent != null && !hidden) {
                SanvyaText(
                    // The arrow is direction, the colour is meaning -- see
                    // `inverse` above.
                    text = "${if (rose) "▲" else "▼"} ${formatPercent(abs(percent))}",
                    style = SanvyaType.statLabel,
                    color = if (good) colors.positive else colors.negative,
                )
            }
        }

        SanvyaText(
            text = if (hidden) {
                S.Dashboard.statHidden(res)
            } else {
                S.Dashboard.statVsLastMonth(res, formatMoney(card.previousMinor, base))
            },
            style = SanvyaType.statLabel,
            color = colors.text3,
            modifier = Modifier.padding(top = 4.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** Web's `••••••` mask, the same string the hero and the account chips use. */
private const val HIDDEN_AMOUNT = "••••••"

/** Web prints `toFixed(1)` and a percent sign. */
private fun formatPercent(value: Double): String = String.format("%.1f%%", value)

/**
 * Counts a figure up to [target] whenever it changes.
 *
 * Web's easing is `easeOutExpo` over 900 ms -- fast out of the gate, long
 * settle, so it reads as "landing on" a figure rather than as an odometer roll.
 * `CubicBezierEasing(0.16, 1, 0.3, 1)` is the closest standard curve and is
 * already the app's own page-in easing shape.
 *
 * Skipped entirely when amounts are hidden (there is nothing to count to) and
 * when the device has animations turned off. `ANIMATOR_DURATION_SCALE == 0` is
 * Android's own "prefers reduced motion": someone who has turned animations off
 * system-wide gets the final value immediately, exactly as web gives it to
 * someone with `prefers-reduced-motion: reduce`.
 */
@Composable
private fun countUp(target: Long, enabled: Boolean): Long {
    val context = LocalContext.current
    val animationsOff = remember(context) {
        runCatching {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f
        }.getOrDefault(false)
    }
    if (!enabled || animationsOff) return target

    val value by animateFloatAsState(
        targetValue = target.toFloat(),
        animationSpec = tween(durationMillis = COUNT_UP_MS, easing = COUNT_UP_EASING),
        label = "statCountUp",
    )
    // Back to an integer before it is formatted: money is minor units and a
    // half-way float must never reach `formatMoney`.
    return value.roundToLong()
}

private const val COUNT_UP_MS = 900
private val COUNT_UP_EASING = CubicBezierEasing(0.16f, 1f, 0.3f, 1f)
