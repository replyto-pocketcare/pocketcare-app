package care.pocket.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class BudgetUiModel(
    val id: String,
    val name: String,
    val period: String,
    val spentFormatted: String,
    val limitFormatted: String,
    val progress: Float, // 0.0 to 1.0+
    val categories: List<String>
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BudgetsScreen(
    onAddBudgetClick: () -> Unit = {},
    onBudgetClick: (BudgetUiModel) -> Unit = {}
) {
    val sampleBudgets = remember {
        listOf(
            BudgetUiModel("1", "Monthly Dining Out", "monthly", "₹6,400", "₹8,000", 0.80f, listOf("Food & Dining")),
            BudgetUiModel("2", "Groceries & Household", "monthly", "₹11,200", "₹15,000", 0.74f, listOf("Groceries")),
            BudgetUiModel("3", "Entertainment & Leisure", "monthly", "₹5,200", "₹4,000", 1.30f, listOf("Shopping", "Entertainment")),
            BudgetUiModel("4", "Fuel & Transport", "monthly", "₹2,100", "₹5,000", 0.42f, listOf("Transport"))
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Budgets",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                },
                actions = {
                    TextButton(onClick = onAddBudgetClick) {
                        Text(
                            "+ Add",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Terracotta
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            items(sampleBudgets) { budget ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onBudgetClick(budget) },
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(18.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column {
                                Text(
                                    budget.name,
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    "${budget.period.replaceFirstChar { it.uppercase() }} • ${budget.categories.joinToString()}",
                                    fontSize = 12.sp,
                                    color = InkSoft
                                )
                            }
                            BudgetStatusTag(budget.progress)
                        }

                        Spacer(modifier = Modifier.height(14.dp))

                        LinearProgressIndicator(
                            progress = { budget.progress.coerceAtMost(1.0f) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(8.dp)
                                .clip(RoundedCornerShape(4.dp)),
                            color = when {
                                budget.progress > 1.0f -> Terracotta
                                budget.progress > 0.8f -> Color(0xFFC08A3E)
                                else -> Sage
                            },
                            trackColor = Clay100
                        )

                        Spacer(modifier = Modifier.height(10.dp))

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                "Spent: ${budget.spentFormatted}",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Text(
                                "Limit: ${budget.limitFormatted}",
                                fontSize = 13.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = InkSoft
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun BudgetStatusTag(progress: Float) {
    val (label, bg, fg) = when {
        progress > 1.0f -> Triple("Over Budget", TerracottaSoft, Cream)
        progress > 0.8f -> Triple("Near Limit", Color(0xFFE8C88A), Ink)
        else -> Triple("On Track", Sage, Cream)
    }

    Surface(
        shape = RoundedCornerShape(8.dp),
        color = bg
    ) {
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = fg,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
        )
    }
}
