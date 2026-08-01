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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class GoalUiModel(
    val id: String,
    val name: String,
    val currentFormatted: String,
    val targetFormatted: String,
    val targetDate: String,
    val progress: Float // 0.0 to 1.0
)

data class CashflowUiModel(
    val id: String,
    val title: String,
    val amountFormatted: String,
    val expectedDate: String,
    val isIncome: Boolean,
    val status: String // planned, completed, skipped
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GoalsScreen(
    onAddGoalClick: () -> Unit = {},
    onGoalClick: (GoalUiModel) -> Unit = {}
) {
    var selectedTab by remember { mutableStateOf(0) } // 0: Goals, 1: Cashflow

    val sampleGoals = remember {
        listOf(
            GoalUiModel("1", "Emergency Fund (6 Months)", "₹3,50,000", "₹5,00,000", "Dec 2026", 0.70f),
            GoalUiModel("2", "Japan Vacation", "₹1,20,000", "₹2,50,000", "Oct 2027", 0.48f),
            GoalUiModel("3", "MacBook Pro Upgrade", "₹1,80,000", "₹2,00,000", "Mar 2027", 0.90f)
        )
    }

    val sampleCashflows = remember {
        listOf(
            CashflowUiModel("1", "Annual Bonus", "+₹1,50,000", "15 Aug 2026", isIncome = true, status = "planned"),
            CashflowUiModel("2", "Health Insurance Premium", "-₹24,000", "01 Sep 2026", isIncome = false, status = "planned"),
            CashflowUiModel("3", "Fixed Deposit Maturity", "+₹50,000", "10 Jul 2026", isIncome = true, status = "completed")
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Goals & Cashflow",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                },
                actions = {
                    TextButton(onClick = onAddGoalClick) {
                        Text(
                            "+ Add Goal",
                            fontSize = 15.sp,
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = (selectedTab == 0),
                    onClick = { selectedTab = 0 },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                ) { Text("Goals") }

                SegmentedButton(
                    selected = (selectedTab == 1),
                    onClick = { selectedTab = 1 },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                ) { Text("Cashflow") }
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (selectedTab == 0) {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    items(sampleGoals) { goal ->
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onGoalClick(goal) },
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
                                    Text(
                                        goal.name,
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Text(
                                        "Target: ${goal.targetDate}",
                                        fontSize = 12.sp,
                                        color = InkSoft
                                    )
                                }

                                Spacer(modifier = Modifier.height(12.dp))

                                LinearProgressIndicator(
                                    progress = { goal.progress },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(8.dp)
                                        .clip(RoundedCornerShape(4.dp)),
                                    color = Terracotta,
                                    trackColor = Clay100
                                )

                                Spacer(modifier = Modifier.height(10.dp))

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        "Saved: ${goal.currentFormatted}",
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = Sage
                                    )
                                    Text(
                                        "Goal: ${goal.targetFormatted}",
                                        fontSize = 13.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                        }
                    }
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(sampleCashflows) { cf ->
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(14.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column {
                                    Text(
                                        cf.title,
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Spacer(modifier = Modifier.height(4.dp))
                                    Text(
                                        "Expected: ${cf.expectedDate}",
                                        fontSize = 12.sp,
                                        color = InkSoft
                                    )
                                }
                                Column(horizontalAlignment = Alignment.End) {
                                    Text(
                                        cf.amountFormatted,
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (cf.isIncome) Sage else Terracotta
                                    )
                                    Spacer(modifier = Modifier.height(2.dp))
                                    Surface(
                                        shape = RoundedCornerShape(6.dp),
                                        color = if (cf.status == "completed") Sage.copy(alpha = 0.2f) else Clay100
                                    ) {
                                        Text(
                                            cf.status.replaceFirstChar { it.uppercase() },
                                            fontSize = 10.sp,
                                            fontWeight = FontWeight.Medium,
                                            color = Ink,
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
