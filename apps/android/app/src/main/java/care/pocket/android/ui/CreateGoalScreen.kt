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
fun CreateGoalScreen(
    onDismiss: () -> Unit = {},
    onSave: (name: String, targetRupees: Long, targetDate: String, initialAllocation: Long) -> Unit = { _, _, _, _ -> }
) {
    var name by remember { mutableStateOf("") }
    var targetText by remember { mutableStateOf("") }
    var targetDate by remember { mutableStateOf("Dec 2026") }
    var initialAllocationText by remember { mutableStateOf("0") }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("New Financial Goal", fontWeight = FontWeight.Bold) },
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
                label = { Text("Goal Name") },
                placeholder = { Text("e.g. Emergency Fund or Japan Vacation") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            OutlinedTextField(
                value = targetText,
                onValueChange = { targetText = it.filter { char -> char.isDigit() } },
                label = { Text("Target Amount (₹)") },
                placeholder = { Text("500000") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            OutlinedTextField(
                value = targetDate,
                onValueChange = { targetDate = it },
                label = { Text("Target Date") },
                placeholder = { Text("e.g. Dec 2026") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            OutlinedTextField(
                value = initialAllocationText,
                onValueChange = { initialAllocationText = it.filter { char -> char.isDigit() } },
                label = { Text("Initial Saved / Allocated Amount (₹)") },
                placeholder = { Text("0") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    val target = targetText.toLongOrNull() ?: 0L
                    val initial = initialAllocationText.toLongOrNull() ?: 0L
                    onSave(name.ifEmpty { "New Goal" }, target, targetDate, initial)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Create Goal", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
