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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import care.pocket.android.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateBudgetScreen(
    onDismiss: () -> Unit = {},
    onSave: (name: String, limitRupees: Long, period: String, categories: List<String>) -> Unit = { _, _, _, _ -> }
) {
    var name by remember { mutableStateOf("") }
    var limitText by remember { mutableStateOf("") }
    var period by remember { mutableStateOf("monthly") }
    var selectedCategories by remember { mutableStateOf(setOf("Food & Dining")) }

    val categoriesList = listOf("Food & Dining", "Groceries", "Shopping", "Transport", "Bills & Utilities", "Entertainment")

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New Budget", fontWeight = FontWeight.Bold) },
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
                label = { Text("Budget Name") },
                placeholder = { Text("e.g. Monthly Dining Out") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            OutlinedTextField(
                value = limitText,
                onValueChange = { limitText = it.filter { char -> char.isDigit() } },
                label = { Text("Limit Amount (₹)") },
                placeholder = { Text("8000") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Text("Recurrence Period", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                listOf("monthly" to "Monthly", "weekly" to "Weekly", "yearly" to "Yearly").forEach { (pKey, pLabel) ->
                    FilterChip(
                        selected = (period == pKey),
                        onClick = { period = pKey },
                        label = { Text(pLabel, fontSize = 12.sp) },
                        modifier = Modifier.weight(1f),
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = Terracotta,
                            selectedLabelColor = Cream
                        )
                    )
                }
            }

            Text("Category Filter", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                categoriesList.chunked(2).forEach { catRow ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        catRow.forEach { cat ->
                            val isSelected = cat in selectedCategories
                            FilterChip(
                                selected = isSelected,
                                onClick = {
                                    selectedCategories = if (isSelected) {
                                        selectedCategories - cat
                                    } else {
                                        selectedCategories + cat
                                    }
                                },
                                label = { Text(cat, fontSize = 12.sp) },
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

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    val limit = limitText.toLongOrNull() ?: 0L
                    onSave(name.ifEmpty { "New Budget" }, limit, period, selectedCategories.toList())
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Create Budget", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
