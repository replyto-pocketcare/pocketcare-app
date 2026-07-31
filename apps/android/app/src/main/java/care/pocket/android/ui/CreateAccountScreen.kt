package care.pocket.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateAccountScreen(
    onDismiss: () -> Unit = {},
    onSave: (name: String, type: String, currency: String, openingBalance: Long, allowNegative: Boolean) -> Unit = { _, _, _, _, _ -> }
) {
    var name by remember { mutableStateOf("") }
    var selectedType by remember { mutableStateOf("savings") }
    var currency by remember { mutableStateOf("INR") }
    var openingBalanceText by remember { mutableStateOf("0") }
    var allowNegative by remember { mutableStateOf(false) }
    var includeInNetWorth by remember { mutableStateOf(true) }

    val accountTypes = listOf(
        "savings" to "Savings Account",
        "current" to "Current Account",
        "credit_card" to "Credit Card",
        "cash" to "Cash Wallet",
        "stocks" to "Stock Portfolio",
        "mutual_funds" to "Mutual Funds"
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New Account", fontWeight = FontWeight.Bold) },
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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Account Name") },
                placeholder = { Text("e.g. HDFC Salary Account") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Text("Account Type", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                accountTypes.chunked(2).forEach { rowTypes ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowTypes.forEach { (typeKey, typeLabel) ->
                            FilterChip(
                                selected = (selectedType == typeKey),
                                onClick = {
                                    selectedType = typeKey
                                    if (typeKey == "credit_card") {
                                        allowNegative = true
                                    }
                                },
                                label = { Text(typeLabel, fontSize = 12.sp) },
                                modifier = Modifier.weight(1f),
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = Terracotta,
                                    selectedLabelColor = Cream
                                )
                            )
                        }
                    }
                }
            }

            OutlinedTextField(
                value = openingBalanceText,
                onValueChange = { openingBalanceText = it.filter { char -> char.isDigit() || char == '-' } },
                label = { Text("Opening Balance (₹)") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("Allow Overdraft / Negative Balance", fontWeight = FontWeight.Medium, fontSize = 14.sp)
                    Text("Permit balance to drop below ₹0", fontSize = 12.sp, color = InkSoft)
                }
                Switch(
                    checked = allowNegative,
                    onCheckedChange = { allowNegative = it },
                    colors = SwitchDefaults.colors(checkedThumbColor = Terracotta, checkedTrackColor = TerracottaSoft)
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("Include in Net Worth", fontWeight = FontWeight.Medium, fontSize = 14.sp)
                    Text("Count in overall net worth calculation", fontSize = 12.sp, color = InkSoft)
                }
                Switch(
                    checked = includeInNetWorth,
                    onCheckedChange = { includeInNetWorth = it },
                    colors = SwitchDefaults.colors(checkedThumbColor = Terracotta, checkedTrackColor = TerracottaSoft)
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    val amtRupees = openingBalanceText.toLongOrNull() ?: 0L
                    onSave(name.ifEmpty { "New Account" }, selectedType, currency, amtRupees * 100, allowNegative)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Create Account", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
