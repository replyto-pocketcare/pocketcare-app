package com.sanvya.app.ui.transactions

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Transactions list — ported from apps/web/app/transactions/page.tsx +
 * src/ui/TransactionTile.tsx per docs/mobile/screen-specs/transactions.md.
 * Split-row collapsing (a Splits-feature concern) is explicitly deferred —
 * see spec's Scope section.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionsScreen(
    onBack: () -> Unit = {},
    onAddTransaction: () -> Unit = {},
    onEditTransaction: (String) -> Unit = {},
    viewModel: TransactionsViewModel = viewModel(),
) {
    val items by viewModel.items.collectAsState()
    val query by viewModel.query.collectAsState()
    val typeFilter by viewModel.typeFilter.collectAsState()
    val colors = LocalSanvyaColors.current

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text(S.Transactions.title(sRes()), fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = S.Translation.commonBack(sRes()), tint = colors.text2)
                    }
                },
                actions = {
                    IconButton(onClick = onAddTransaction) {
                        Icon(Icons.Default.Add, contentDescription = S.Transactions.addTitle(sRes()), tint = colors.accent)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            Column(Modifier.padding(16.dp, 12.dp, 16.dp, 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = query,
                    onValueChange = viewModel::setQuery,
                    placeholder = { Text("Search note or label") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TX_TYPE_FILTERS.forEach { ty ->
                        val selected = ty == typeFilter
                        AssistChip(
                            onClick = { viewModel.setTypeFilter(ty) },
                            label = { Text(ty.replaceFirstChar { it.uppercase() }, fontSize = 12.sp) },
                            colors = AssistChipDefaults.assistChipColors(
                                containerColor = if (selected) colors.accent else colors.surface2,
                                labelColor = if (selected) Color.White else colors.text,
                            ),
                        )
                    }
                }
            }

            if (items.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(S.Transactions.noMatching(sRes()), color = colors.text2, fontSize = 14.sp)
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(16.dp, 4.dp, 16.dp, 24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(items, key = { it.id }) { item ->
                        TransactionRowCard(item = item, colors = colors, onClick = { onEditTransaction(item.id) })
                    }
                }
            }
        }
    }
}

@Composable
private fun TransactionRowCard(
    item: TransactionListItem,
    colors: com.sanvya.app.theme.SanvyaColors,
    onClick: () -> Unit,
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
            Text(item.title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
