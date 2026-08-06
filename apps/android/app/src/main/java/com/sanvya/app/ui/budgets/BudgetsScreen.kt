package com.sanvya.app.ui.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaRadius
import kotlin.math.roundToInt

/**
 * Ported from apps/web/app/budgets/page.tsx's list + docs/mobile/
 * screen-specs/budgets.md. Was completely unbuilt before this pass
 * (2026-08-06, task #24) -- BudgetsViewModel existed but no Screen
 * consumed it and no nav route reached it (drawer routed to a
 * "coming_soon/Budgets" placeholder).
 *
 * Web's edit affordance is an in-place expand within the same card, not a
 * separate screen -- this uses separate Create/EditBudgetScreen routes
 * instead, matching this app's own established Accounts/Transactions
 * pattern (translate the logic, not the exact widget shape).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BudgetsScreen(
    onBack: () -> Unit = {},
    onAddBudget: () -> Unit = {},
    onEditBudget: (String) -> Unit = {},
    viewModel: BudgetsViewModel = viewModel(),
) {
    val budgets by viewModel.budgets.collectAsState()
    val colors = LocalSanvyaColors.current

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("Budgets", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2)
                    }
                },
                actions = {
                    IconButton(onClick = onAddBudget) {
                        Icon(Icons.Default.Add, contentDescription = "New budget", tint = colors.accent)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        if (budgets.isEmpty()) {
            Box(modifier = Modifier.padding(padding).fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("◔", fontSize = 26.sp)
                    Text("No budgets yet", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(
                        "Set a spending limit to get alerts before you go over.",
                        fontSize = 14.sp,
                        color = colors.text2,
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                    Button(onClick = onAddBudget, modifier = Modifier.padding(top = 4.dp)) {
                        Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Create first budget")
                    }
                }
            }
        } else {
            Column(
                modifier = Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                budgets.forEach { budget ->
                    BudgetRowCard(budget = budget, onClick = { onEditBudget(budget.id) })
                }
            }
        }
    }
}

@Composable
private fun BudgetRowCard(budget: BudgetUiModel, onClick: () -> Unit) {
    val colors = LocalSanvyaColors.current
    val tint = when (budget.progressColor) {
        ProgressColor.POSITIVE -> colors.positive
        ProgressColor.WARNING -> colors.warning
        ProgressColor.NEGATIVE -> colors.negative
    }
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = colors.surface),
        shape = RoundedCornerShape(SanvyaRadius.radiusLg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column {
                    Text(budget.title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = colors.text)
                    Text(budget.timeframeText, fontSize = 12.sp, color = colors.text2)
                }
                Text("${(budget.progress * 100).roundToInt()}%", fontSize = 12.sp, color = colors.text2)
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .clip(RoundedCornerShape(50))
                    .background(colors.border),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(fraction = budget.progress.coerceIn(0.0, 1.0).toFloat())
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(50))
                        .background(tint),
                )
            }
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(budget.spentFormatted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(budget.remainingOrOverText, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = tint)
            }
        }
    }
}
