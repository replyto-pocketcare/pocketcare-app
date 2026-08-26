package com.sanvya.app.ui.transactions

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius

/**
 * One transaction, as a row.
 *
 * Was `private` inside TransactionsScreen.kt. Promoted 2026-08-25 for the
 * dashboard's Recent Activity tile — web renders the same `<TransactionTile>`
 * on Transactions, Search, Statements and the dashboard, and a second copy here
 * is the re-inlining this audit's component inventory exists to prevent.
 */
@Composable
fun TransactionRowCard(
    item: TransactionListItem,
    onClick: () -> Unit,
    colors: com.sanvya.app.theme.SanvyaColors = LocalSanvyaColors.current,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(SanvyaRadius.radiusSm))
            .background(colors.surface)
            .clickable(onClick = onClick)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier.size(34.dp).clip(CircleShape).background(item.avatarColor),
            contentAlignment = Alignment.Center,
        ) {
            Text(item.avatarLetter, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
        }
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    item.title,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (item.isSplit) SplitChip(colors)
            }
            if (item.subtitle.isNotEmpty()) {
                Text(item.subtitle, fontSize = 11.5.sp, color = colors.text2, maxLines = 2)
            }
            if (item.tags.isNotEmpty()) {
                Text(
                    item.tags.joinToString("  ·  ") { it.text },
                    fontSize = 11.5.sp,
                    color = colors.text2,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            item.accountName?.let {
                Text(it, fontSize = 11.5.sp, color = colors.text2)
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                item.amountFormatted,
                fontSize = 14.5.sp,
                fontWeight = FontWeight.Bold,
                color = if (item.amountColor == TxAmountColor.POSITIVE) colors.positive else colors.text,
            )
            Text(item.dateFormatted, fontSize = 11.sp, color = colors.text2)
        }
    }
}

/**
 * The "Split" pill on a collapsed split row -- web's `SplitChip`.
 *
 * Its own composable rather than an inline Box: three screens list
 * transactions, and the chip belongs to the row, not to any one of them.
 */
@Composable
private fun SplitChip(colors: com.sanvya.app.theme.SanvyaColors) {
    Text(
        S.Transactions.splitChip(sRes()).uppercase(),
        fontSize = 10.5.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.3.sp,
        color = colors.accent,
        maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .background(colors.accentGhost)
            .padding(horizontal = 7.dp, vertical = 1.dp),
    )
}
