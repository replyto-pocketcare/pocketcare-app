package care.pocket.android.ui

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

data class StatementTxnUiModel(
    val id: String,
    val date: String,
    val narration: String,
    val amountFormatted: String,
    val isDebit: Boolean,
    val category: String
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatementImportScreen(
    onDismiss: () -> Unit = {},
    onImportConfirmed: (txnsCount: Int) -> Unit = {}
) {
    var selectedAccount by remember { mutableStateOf("HDFC Primary Savings (*4821)") }
    var fileSelected by remember { mutableStateOf("HDFC_Statement_July2026.pdf") }

    val parsedTxns = remember {
        listOf(
            StatementTxnUiModel("1", "30 Jul 2026", "UPI/Swiggy/29841029", "-₹640", true, "Food & Dining"),
            StatementTxnUiModel("2", "28 Jul 2026", "SALARY CREDIT ACME CORP", "+₹1,25,000", false, "Income"),
            StatementTxnUiModel("3", "25 Jul 2026", "UPI/Airtel Broadband/58129", "-₹1,179", true, "Bills & Utilities"),
            StatementTxnUiModel("4", "22 Jul 2026", "POS DMART SUPERMARKET", "-₹4,320", true, "Groceries")
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Import Bank Statement", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    TextButton(onClick = onDismiss) {
                        Text("Cancel", color = InkSoft)
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
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = Clay100)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("📄 Selected File: $fileSelected", fontWeight = FontWeight.Bold, fontSize = 13.sp)
                    Text("Target Account: $selectedAccount", fontSize = 12.sp, color = InkSoft)
                    Spacer(modifier = Modifier.height(4.dp))
                    Surface(shape = RoundedCornerShape(6.dp), color = Sage) {
                        Text(
                            "✓ 4 Transactions Parsed • Zero Checksum Drift",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = Cream,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                }
            }

            Text("Parsed Transactions Preview", fontWeight = FontWeight.Bold, fontSize = 15.sp)

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(parsedTxns) { txn ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(14.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(txn.narration, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                                Spacer(modifier = Modifier.height(2.dp))
                                Text("${txn.date} • ${txn.category}", fontSize = 12.sp, color = InkSoft)
                            }
                            Text(
                                txn.amountFormatted,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                color = if (txn.isDebit) Terracotta else Sage
                            )
                        }
                    }
                }
            }

            Button(
                onClick = { onImportConfirmed(parsedTxns.size) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Import & Reconcile Transactions", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
