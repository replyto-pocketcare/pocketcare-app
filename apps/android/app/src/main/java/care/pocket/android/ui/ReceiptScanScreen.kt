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

data class ReceiptLineItemUiModel(
    val id: String,
    val description: String,
    val quantity: Int,
    val amountFormatted: String,
    val assignedMember: String
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptScanScreen(
    onDismiss: () -> Unit = {},
    onSave: (merchant: String, totalRupees: Long, lineItems: List<ReceiptLineItemUiModel>) -> Unit = { _, _, _ -> }
) {
    var merchant by remember { mutableStateOf("Olive Garden Restaurant") }
    var date by remember { mutableStateOf("01 Aug 2026") }
    var totalText by remember { mutableStateOf("3450") }

    val lineItems = remember {
        mutableStateListOf(
            ReceiptLineItemUiModel("1", "Pasta Carbonara", 2, "₹1,200", "You"),
            ReceiptLineItemUiModel("2", "Margherita Pizza", 1, "₹850", "Rahul"),
            ReceiptLineItemUiModel("3", "Tiramisu Dessert", 2, "₹600", "Priya"),
            ReceiptLineItemUiModel("4", "Tax & Service Charge", 1, "₹800", "Everyone (Proportional)")
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Receipt Scan & Split", fontWeight = FontWeight.Bold) },
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
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(140.dp),
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = Clay100)
            ) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("📷 Photo / OCR Scan Attached", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Ink)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("AI detected 4 line items with 100% confidence", fontSize = 12.sp, color = InkSoft)
                    }
                }
            }

            OutlinedTextField(
                value = merchant,
                onValueChange = { merchant = it },
                label = { Text("Merchant Name") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = totalText,
                    onValueChange = { totalText = it.filter { char -> char.isDigit() } },
                    label = { Text("Total (₹)") },
                    modifier = Modifier.weight(1f),
                    singleLine = true
                )
                OutlinedTextField(
                    value = date,
                    onValueChange = { date = it },
                    label = { Text("Date") },
                    modifier = Modifier.weight(1f),
                    singleLine = true
                )
            }

            Text("Itemized Line Items", fontWeight = FontWeight.Bold, fontSize = 15.sp)

            lineItems.forEach { item ->
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
                            Text(item.description, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                            Text("Qty: ${item.quantity} • Assigned: ${item.assignedMember}", fontSize = 12.sp, color = InkSoft)
                        }
                        Text(item.amountFormatted, fontWeight = FontWeight.Bold, fontSize = 14.sp, color = Terracotta)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    onSave(merchant, totalText.toLongOrNull() ?: 0L, lineItems)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Save Receipt & Allocate Shares", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
