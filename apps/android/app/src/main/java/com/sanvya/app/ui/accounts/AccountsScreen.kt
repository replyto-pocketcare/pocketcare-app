package com.sanvya.app.ui.accounts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import com.sanvya.app.ui.accountColor
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes

/**
 * Accounts list — ported from apps/web/app/accounts/page.tsx per
 * docs/mobile/screen-specs/accounts.md. MultiCurrencyCard is explicitly
 * deferred (see spec's Scope section) -- not built, not faked.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountsScreen(
    onBack: () -> Unit = {},
    onNewAccount: () -> Unit = {},
    onEditAccount: (String) -> Unit = {},
    viewModel: AccountsViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalSanvyaColors.current

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text(S.Accounts.title(sRes()), fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = S.Translation.commonBack(sRes()), tint = colors.text2)
                    }
                },
                actions = {
                    if (uiState.archivedCount > 0) {
                        AssistChip(
                            onClick = { viewModel.toggleShowArchived() },
                            label = {
                                Text(
                                    if (uiState.showArchived) S.Accounts.hideArchived(sRes()) else "Show archived (${uiState.archivedCount})",
                                    fontSize = 12.sp,
                                )
                            },
                            modifier = Modifier.padding(end = 8.dp),
                        )
                    }
                    IconButton(onClick = onNewAccount) {
                        Icon(Icons.Default.Add, contentDescription = S.Accounts.newAccount(sRes()), tint = colors.accent)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        if (uiState.visible.isEmpty()) {
            Box(
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(S.Accounts.noAccounts(sRes()), color = colors.text2, fontSize = 14.sp)
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 260.dp),
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(uiState.visible, key = { it.id }) { acct ->
                    AccountCard(
                        acct = acct,
                        colors = colors,
                        onToggleIncludeInNetWorth = { viewModel.toggleIncludeInNetWorth(acct.id, acct.includeInNetWorth) },
                        onUnarchive = { viewModel.setArchived(acct.id, false) },
                        onEdit = { onEditAccount(acct.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun AccountCard(
    acct: AccountUiModel,
    colors: com.sanvya.app.theme.SanvyaColors,
    onToggleIncludeInNetWorth: () -> Unit,
    onUnarchive: () -> Unit,
    onEdit: () -> Unit,
) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(SanvyaRadius.radiusLg))
            .background(colors.surface)
            .alpha(if (acct.isArchived) 0.6f else 1f),
    ) {
        Box(
            modifier = Modifier
                .width(6.dp)
                .fillMaxHeight()
                .background(accountColor(acct.color, acct.id)),
        )
        Column(
            modifier = Modifier.padding(18.dp).weight(1f),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = "${acct.type.replace("_", " ")} · ${acct.currency}" + if (acct.isArchived) " · Archived" else "",
                fontSize = 12.sp,
                color = colors.text2,
            )
            Text(acct.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(acct.balance, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = colors.text)
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (acct.isArchived) {
                    AssistChip(onClick = onUnarchive, label = { Text(S.Accounts.unarchive(sRes()), fontSize = 12.sp) })
                } else {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.clickable(onClick = onToggleIncludeInNetWorth),
                    ) {
                        Checkbox(checked = acct.includeInNetWorth, onCheckedChange = { onToggleIncludeInNetWorth() })
                        Text(S.Accounts.inNetWorth(sRes()), fontSize = 12.sp, color = colors.text2)
                    }
                }
                AssistChip(onClick = onEdit, label = { Text(S.Accounts.edit(sRes()), fontSize = 12.sp) })
            }
        }
    }
}
