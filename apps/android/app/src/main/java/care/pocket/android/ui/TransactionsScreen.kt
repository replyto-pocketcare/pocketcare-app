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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

data class TransactionUiModel(
    val id: String,
    val description: String,
    val amount: String,
    val date: String,
    val accountName: String,
    val categoryName: String,
    val isIncome: Boolean = false
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TransactionsScreen(
    onAddTransactionClick: () -> Unit = {},
    onTransactionClick: (TransactionUiModel) -> Unit = {}
) {
    var searchQuery by remember { mutableStateOf("") }
    var selectedFilter by remember { mutableStateOf("All") }

    val filterOptions = listOf("All", "Expense", "Income")

    val sampleTxns = remember {
        listOf(
            TransactionUiModel("1", "Swiggy Gourmet", "-₹840.00", "Today", "HDFC Savings", "Food & Dining"),
            TransactionUiModel("2", "Salary Credit", "+₹85,000.00", "Yesterday", "SBI Salary Account", "Salary", isIncome = true),
            TransactionUiModel("3", "Reliance Fresh Groceries", "-₹2,350.00", "29 Jul", "HDFC Savings", "Groceries"),
            TransactionUiModel("4", "Uber Ride", "-₹420.00", "28 Jul", "ICICI Credit Card", "Transport"),
            TransactionUiModel("5", "Splitwise Settlement (Ankit)", "+₹1,500.00", "26 Jul", "HDFC Savings", "Transfer", isIncome = true)
        )
    }

    val filteredTxns = sampleTxns.filter { txn ->
        val matchesSearch = txn.description.contains(searchQuery, ignoreCase = true) ||
                txn.categoryName.contains(searchQuery, ignoreCase = true)
        val matchesFilter = when (selectedFilter) {
            "Expense" -> !txn.isIncome
            "Income" -> txn.isIncome
            else -> true
        }
        matchesSearch && matchesFilter
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        "Transactions",
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                },
                actions = {
                    TextButton(onClick = onAddTransactionClick) {
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
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                placeholder = { Text("Search transactions...") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Spacer(modifier = Modifier.height(12.dp))

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                filterOptions.forEach { filter ->
                    FilterChip(
                        selected = (selectedFilter == filter),
                        onClick = { selectedFilter = filter },
                        label = { Text(filter, fontSize = 12.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = Terracotta,
                            selectedLabelColor = Cream
                        )
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(filteredTxns) { txn ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onTransactionClick(txn) },
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
                                    txn.description,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Surface(
                                        shape = RoundedCornerShape(6.dp),
                                        color = Clay100
                                    ) {
                                        Text(
                                            txn.categoryName,
                                            fontSize = 11.sp,
                                            fontWeight = FontWeight.Medium,
                                            color = Ink,
                                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                        )
                                    }
                                    Spacer(modifier = Modifier.width(8.dp))
                                    Text(
                                        "${txn.accountName} • ${txn.date}",
                                        fontSize = 12.sp,
                                        color = InkSoft
                                    )
                                }
                            }
                            Text(
                                txn.amount,
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (txn.isIncome) Sage else MaterialTheme.colorScheme.onSurface
                            )
                        }
                    }
                }
            }
        }
    }
}
