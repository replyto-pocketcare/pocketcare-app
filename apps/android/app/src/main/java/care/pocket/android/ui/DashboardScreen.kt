package care.pocket.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class DummyAccount(val id: String, val name: String, val balance: String, val type: String)
data class DummyTxn(val id: String, val description: String, val amount: String, val date: String, val type: String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen() {
    val dummyAccounts = listOf(
        DummyAccount("1", "Main Savings", "₹1,42,500.00", "savings"),
        DummyAccount("2", "HDFC Credit Card", "₹-18,200.00", "credit_card"),
        DummyAccount("3", "Cash Wallet", "₹3,400.00", "cash")
    )

    val dummyTxns = listOf(
        DummyTxn("1", "Grocery Market", "-₹1,250.00", "Today", "expense"),
        DummyTxn("2", "Salary Credit", "+₹85,000.00", "Yesterday", "income"),
        DummyTxn("3", "Coffee & Snacks", "-₹340.00", "28 Jul", "expense"),
        DummyTxn("4", "Split Settlement (Rahul)", "+₹1,200.00", "26 Jul", "transfer")
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "PocketCare",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
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
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Net Worth Summary Card
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = Terracotta)
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(24.dp)
                    ) {
                        Text(
                            text = "NET WORTH",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Cream.copy(alpha = 0.8f),
                            letterSpacing = 1.sp
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "₹1,27,700.00",
                            fontSize = 32.sp,
                            fontWeight = FontWeight.Bold,
                            color = Cream
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column {
                                Text("Assets", fontSize = 11.sp, color = Cream.copy(alpha = 0.7f))
                                Text("₹1,45,900", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Cream)
                            }
                            Column {
                                Text("Liabilities", fontSize = 11.sp, color = Cream.copy(alpha = 0.7f))
                                Text("₹18,200", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Cream)
                            }
                        }
                    }
                }
            }

            // Quick Actions
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    QuickActionButton(symbol = "+", label = "Add Expense")
                    QuickActionButton(symbol = "⇄", label = "Transfer")
                    QuickActionButton(symbol = "👥", label = "Settle Up")
                }
            }

            // Accounts Carousel
            item {
                Column {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "Accounts",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onBackground
                        )
                        Text(
                            "→",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onBackground,
                            modifier = Modifier.padding(8.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        items(dummyAccounts) { acct ->
                            Card(
                                modifier = Modifier
                                    .width(180.dp)
                                    .height(110.dp),
                                shape = RoundedCornerShape(16.dp),
                                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                            ) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .padding(16.dp),
                                    verticalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Text(
                                        acct.name,
                                        fontSize = 14.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Text(
                                        acct.balance,
                                        fontSize = 18.sp,
                                        fontWeight = FontWeight.Bold,
                                        color = if (acct.balance.startsWith("₹-")) Terracotta else Sage
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Recent Activity Header
            item {
                Text(
                    "Recent Activity",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onBackground
                )
            }

            // Recent Transactions List
            items(dummyTxns) { txn ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
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
                                txn.description,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            Text(
                                txn.date,
                                fontSize = 12.sp,
                                color = InkSoft
                            )
                        }
                        Text(
                            txn.amount,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (txn.amount.startsWith("+")) Sage else MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun QuickActionButton(symbol: String, label: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surface),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = symbol,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Terracotta
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(label, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onBackground)
    }
}
