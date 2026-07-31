package care.pocket.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateTransactionScreen(
    onDismiss: () -> Unit = {},
    onSave: (description: String, amountRupees: Double, isIncome: Boolean, category: String, account: String) -> Unit = { _, _, _, _, _ -> }
) {
    var amountText by remember { mutableStateOf("0") }
    var description by remember { mutableStateOf("") }
    var transactionType by remember { mutableStateOf("Expense") }
    var selectedCategory by remember { mutableStateOf("Food & Dining") }
    var selectedAccount by remember { mutableStateOf("HDFC Savings") }

    val categories = listOf("Food & Dining", "Groceries", "Shopping", "Transport", "Bills & Utilities", "Salary", "Transfer")
    val accounts = listOf("HDFC Savings", "SBI Salary Account", "ICICI Credit Card", "Cash Wallet")

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New Transaction", fontWeight = FontWeight.Bold) },
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
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Type Segment Control
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = (transactionType == "Expense"),
                    onClick = { transactionType = "Expense" },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 3)
                ) { Text("Expense") }

                SegmentedButton(
                    selected = (transactionType == "Income"),
                    onClick = { transactionType = "Income" },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 3)
                ) { Text("Income") }

                SegmentedButton(
                    selected = (transactionType == "Transfer"),
                    onClick = { transactionType = "Transfer" },
                    shape = SegmentedButtonDefaults.itemShape(index = 2, count = 3)
                ) { Text("Transfer") }
            }

            // Amount Display & Input
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(vertical = 12.dp)
            ) {
                Text("AMOUNT", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = InkSoft, letterSpacing = 1.sp)
                Spacer(modifier = Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("₹", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = Terracotta)
                    Spacer(modifier = Modifier.width(4.dp))
                    OutlinedTextField(
                        value = amountText,
                        onValueChange = { amountText = it.filter { char -> char.isDigit() || char == '.' } },
                        textStyle = LocalTextStyle.current.copy(
                            fontSize = 36.sp,
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Start
                        ),
                        singleLine = true,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color.Transparent,
                            unfocusedBorderColor = Color.Transparent
                        )
                    )
                }
            }

            // Description
            OutlinedTextField(
                value = description,
                onValueChange = { description = it },
                label = { Text("Description") },
                placeholder = { Text("e.g. Swiggy Lunch") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            // Category Chips
            Column(modifier = Modifier.fillMaxWidth()) {
                Text("Category", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Spacer(modifier = Modifier.height(8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    categories.chunked(3).forEach { catRow ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            catRow.forEach { cat ->
                                FilterChip(
                                    selected = (selectedCategory == cat),
                                    onClick = { selectedCategory = cat },
                                    label = { Text(cat, fontSize = 11.sp) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        selectedContainerColor = Terracotta,
                                        selectedLabelColor = Cream
                                    )
                                )
                            }
                        }
                    }
                }
            }

            // Account Chips
            Column(modifier = Modifier.fillMaxWidth()) {
                Text("Account", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Spacer(modifier = Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    accounts.take(3).forEach { acct ->
                        FilterChip(
                            selected = (selectedAccount == acct),
                            onClick = { selectedAccount = acct },
                            label = { Text(acct, fontSize = 11.sp) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = Terracotta,
                                selectedLabelColor = Cream
                            )
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    val amt = amountText.toDoubleOrNull() ?: 0.0
                    onSave(
                        description.ifEmpty { "Transaction" },
                        amt,
                        transactionType == "Income",
                        selectedCategory,
                        selectedAccount
                    )
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Save Transaction", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
