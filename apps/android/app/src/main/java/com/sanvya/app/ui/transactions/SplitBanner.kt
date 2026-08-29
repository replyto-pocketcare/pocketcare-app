package com.sanvya.app.ui.transactions

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.data.repository.SplitParticipant
import com.sanvya.app.data.repository.TransactionSplit
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.formatMoney

/**
 * Shown when this transaction is one leg of a split expense — a port of the
 * `SplitBanner` in apps/web/app/transactions/[id]/edit/page.tsx.
 *
 * One split expense writes up to three private ledger rows, and without this
 * card the user opens one of them and sees a bare amount with nothing to say it
 * belongs to a shared bill. It explains that it is part of one and shows the
 * breakdown — total, your share, who paid, what is owed — with a way into the
 * group, so the split detail is found HERE instead of as three cryptic rows in
 * the list.
 *
 * Renders nothing when [split] is null: an ordinary transaction gets no banner.
 */
@Composable
fun SplitBanner(
    split: TransactionSplit?,
    /** The signed-in user's id, so "You" can be told from everyone else. */
    myUserId: String?,
    onOpenGroup: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (split == null) return
    val colors = LocalSanvyaColors.current
    val currency = split.currency
    val mine = split.participants.find { it.userId == myUserId }
    val myShare = mine?.shareAmount ?: 0L
    val myPaid = mine?.paidAmount ?: 0L
    // Positive: you overpaid and are owed the difference. Negative: you owe it.
    // Minor units on both sides, so the subtraction is exact — the same
    // `myPaid - myShare` web does, and the reason there is no scaling here.
    val net = myPaid - myShare

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(SanvyaShape.radiusLg)
            // Web's `border: 1px solid var(--accent-soft)` over
            // `background: var(--accent-ghost)` — a tinted card, deliberately
            // not the neutral `SanvyaCard`, so it reads as an annotation on the
            // form rather than another field of it.
            .background(colors.accentGhost)
            .border(1.dp, colors.accentSoft, SanvyaShape.radiusLg)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                S.Transactions.splitBannerTitle(sRes()),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = colors.text,
            )
            Spacer(Modifier.weight(1f))
            split.groupId?.let { groupId ->
                SanvyaChip(
                    label = split.groupName?.takeIf { it.isNotEmpty() }
                        ?.let { S.Transactions.splitBannerOpenNamed(sRes(), it) }
                        ?: S.Transactions.splitBannerOpenGroup(sRes()),
                    active = false,
                    onClick = { onOpenGroup(groupId) },
                )
            }
        }

        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SplitStat(S.Transactions.splitBannerTotalBill(sRes()), formatMoney(split.total, currency), colors.text, colors)
            SplitStat(S.Transactions.splitBannerYourShare(sRes()), formatMoney(myShare, currency), colors.text, colors)
            SplitStat(S.Transactions.splitBannerYouPaid(sRes()), formatMoney(myPaid, currency), colors.text, colors)
            SplitStat(
                if (net >= 0) S.Transactions.splitBannerOwedToYou(sRes()) else S.Transactions.splitBannerYouOwe(sRes()),
                // `Math.abs` on web: the label already says which direction it
                // is, so the number is never shown with a minus sign.
                formatMoney(kotlin.math.abs(net), currency),
                if (net >= 0) colors.positive else colors.negative,
                colors,
            )
        }

        if (split.participants.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(S.Transactions.splitBannerParticipants(sRes()), fontSize = 12.5.sp, color = colors.text2)
                split.participants.forEach { participant ->
                    SplitParticipantRow(participant, myUserId, currency, colors)
                }
            }
        }

        Text(
            S.Transactions.splitBannerFootnote(sRes()),
            fontSize = 11.5.sp,
            color = colors.text2,
        )
    }
}

/** One "Total bill / ₹1,240" pair from the banner's stat row. */
@Composable
private fun SplitStat(
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color,
    colors: SanvyaColors,
) {
    Column {
        Text(label, fontSize = 13.sp, color = colors.text2)
        Text(value, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = valueColor)
    }
}

@Composable
private fun SplitParticipantRow(
    participant: SplitParticipant,
    myUserId: String?,
    currency: String,
    colors: SanvyaColors,
) {
    // Bound to a local first: `participant.name` is a property of a class in
    // :data, and Kotlin will not smart-cast a public property from another
    // module however it is null-checked.
    val name = participant.name
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            // Web's `p.user_id === me ? "You" : profiles.get(...)?.name ?? "Someone"`.
            // Both fallbacks are translated here; the repository deliberately
            // returns a null name rather than an English one.
            when {
                participant.userId == myUserId -> S.Transactions.you(sRes())
                !name.isNullOrEmpty() -> name
                else -> S.Transactions.someone(sRes())
            },
            fontSize = 12.5.sp,
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Text(
            S.Transactions.splitBannerParticipantLine(
                sRes(),
                formatMoney(participant.shareAmount, currency),
                formatMoney(participant.paidAmount, currency),
            ),
            fontSize = 12.5.sp,
            color = colors.text2,
        )
    }
}
