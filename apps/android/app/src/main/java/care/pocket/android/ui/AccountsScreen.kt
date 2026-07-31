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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class AccountUiModel(
    val id: String,
    val name: String,
    val type: String,
    val currency: String,
    val balance: String,
    val isArchived: Boolean = false,
    val allowNegative: Boolean = false,
    val includeInNetWorth: Boolean = true
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountsScreen(
    onAddAccountClick: () -> Unit = {},
    onEditAccountClick: (AccountUiModel) -> Unit = {}
) {
    val sampleAccounts = remember {
        listOf(
            AccountUiModel("1", "HDFC Savings", "savings", "INR", "₹1,42,500.00"),
            AccountUiModel("2", "SBI Salary Account", "current", "INR", "₹45,200.00"),
            AccountUiModel("3", "ICICI Amazon Pay CC", "credit_card", "INR", "₹-18,200.00", allowNegative = true),
            AccountUiModel("4", "Physical Cash", "cash", "INR", "₹3,400.00"),
            AccountUiModel("5", "Zerodha Stocks", "stocks", "INR", "₹3,15,000.00")
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Accounts",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                },
                actions = {
                    TextButton(onClick = onAddAccountClick) {
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
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(sampleAccounts) { acct ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onEditAccountClick(acct) },
                    shape = RoundedCornerShape(16.dp),
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
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    acct.name,
                                    fontSize = 16.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                AccountTypeChip(acct.type)
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                "Currency: ${acct.currency} ${if (acct.allowNegative) "• Overdraft allowed" else ""}",
                                fontSize = 12.sp,
                                color = InkSoft
                            )
                        }
                        Text(
                            acct.balance,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (acct.balance.startsWith("₹-")) Terracotta else Sage
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun AccountTypeChip(type: String) {
    val label = when (type) {
        "savings" -> "Savings"
        "current" -> "Current"
        "credit_card" -> "Credit Card"
        "cash" -> "Cash"
        "stocks" -> "Stocks"
        "mutual_funds" -> "Mutual Funds"
        else -> type.replaceFirstChar { it.uppercase() }
    }
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = Clay100
    ) {
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = Ink,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
        )
    }
}
