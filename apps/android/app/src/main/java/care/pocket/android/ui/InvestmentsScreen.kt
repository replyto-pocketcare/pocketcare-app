package care.pocket.android.ui

import androidx.compose.foundation.background
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

data class HoldingUiModel(
    val id: String,
    val name: String,
    val symbolExchange: String,
    val assetClass: String, // stock, mutual_fund, sip, crypto, fd
    val quantity: String,
    val currentValueFormatted: String,
    val returnFormatted: String,
    val isPositiveReturn: Boolean
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvestmentsScreen(
    onAddInvestmentClick: () -> Unit = {},
    onHoldingClick: (HoldingUiModel) -> Unit = {}
) {
    var selectedFilter by remember { mutableStateOf("All") }

    val sampleHoldings = remember {
        listOf(
            HoldingUiModel("1", "Reliance Industries", "RELIANCE • NSE", "stock", "25 shares", "₹76,250", "+18.4%", true),
            HoldingUiModel("2", "HDFC Flexi Cap Fund", "INF179KC1951 • MF", "mutual_fund", "1,420 units", "₹1,12,000", "+24.8%", true),
            HoldingUiModel("3", "Nifty 50 Index SIP", "MONTHLY SIP", "sip", "₹5,000/mo", "₹48,000", "+12.1%", true),
            HoldingUiModel("4", "Bitcoin", "BTC • Crypto", "crypto", "0.025 BTC", "₹1,45,000", "-4.2%", false),
            HoldingUiModel("5", "HDFC 1-Year FD", "7.25% p.a.", "fd", "1 Deposit", "₹1,00,000", "+7.25%", true)
        )
    }

    val filters = listOf("All", "Stocks", "Mutual Funds", "SIPs", "Crypto", "FDs")

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Investments",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                },
                actions = {
                    TextButton(onClick = onAddInvestmentClick) {
                        Text(
                            "+ Add",
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
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(20.dp)
                ) {
                    Text("Total Portfolio Value", fontSize = 12.sp, color = InkSoft, fontWeight = FontWeight.Medium)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text("₹4,81,250", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Surface(
                                shape = RoundedCornerShape(6.dp),
                                color = Sage.copy(alpha = 0.2f)
                            ) {
                                Text(
                                    "▲ +₹68,400 (+16.5%)",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Sage,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                                )
                            }
                        }
                        Text("All-Time Return", fontSize = 12.sp, color = InkSoft)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            ScrollableTabRow(
                selectedTabIndex = filters.indexOf(selectedFilter).coerceAtLeast(0),
                edgePadding = 0.dp,
                containerColor = MaterialTheme.colorScheme.background
            ) {
                filters.forEach { filter ->
                    Tab(
                        selected = (selectedFilter == filter),
                        onClick = { selectedFilter = filter },
                        text = { Text(filter, fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(14.dp))

            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(sampleHoldings) { holding ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onHoldingClick(holding) },
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
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    holding.name,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    "${holding.symbolExchange} • ${holding.quantity}",
                                    fontSize = 12.sp,
                                    color = InkSoft
                                )
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    holding.currentValueFormatted,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Spacer(modifier = Modifier.height(2.dp))
                                Text(
                                    holding.returnFormatted,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = if (holding.isPositiveReturn) Sage else Terracotta
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
