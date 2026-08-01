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
fun CreateGroupScreen(
    onDismiss: () -> Unit = {},
    onSave: (name: String, kind: String, members: List<String>, autoSplit: Boolean) -> Unit = { _, _, _, _ -> }
) {
    var name by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf("trip") }
    var selectedMembers by remember { mutableStateOf(setOf("Rahul Sharma", "Ankit Verma")) }
    var startDate by remember { mutableStateOf("") }
    var endDate by remember { mutableStateOf("") }
    var autoSplit by remember { mutableStateOf(false) }

    val availableFriends = listOf("Rahul Sharma", "Ankit Verma", "Priya Patel", "Sneha Gupta")

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (kind == "trip") "New Trip" else "New Group", fontWeight = FontWeight.Bold) },
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
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = (kind == "trip"),
                    onClick = { kind = "trip" },
                    label = { Text("Trip", fontSize = 13.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = Terracotta,
                        selectedLabelColor = Cream
                    )
                )
                FilterChip(
                    selected = (kind == "group"),
                    onClick = { kind = "group" },
                    label = { Text("Group", fontSize = 13.sp) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = Terracotta,
                        selectedLabelColor = Cream
                    )
                )
            }

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(if (kind == "trip") "Trip Name" else "Group Name") },
                placeholder = { Text(if (kind == "trip") "e.g. Goa Beach Trip" else "e.g. Flat 302 Roommates") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = Terracotta,
                    unfocusedBorderColor = Clay200
                )
            )

            Text("Add Friends", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                availableFriends.forEach { friend ->
                    val isSelected = friend in selectedMembers
                    FilterChip(
                        selected = isSelected,
                        onClick = {
                            selectedMembers = if (isSelected) selectedMembers - friend else selectedMembers + friend
                        },
                        label = { Text(friend, fontSize = 12.sp) },
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = Terracotta,
                            selectedLabelColor = Cream
                        )
                    )
                }
            }

            Text("Dates (Optional)", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = startDate,
                    onValueChange = { startDate = it },
                    placeholder = { Text("Start Date") },
                    modifier = Modifier.weight(1f),
                    singleLine = true
                )
                OutlinedTextField(
                    value = endDate,
                    onValueChange = { endDate = it },
                    placeholder = { Text("End Date") },
                    modifier = Modifier.weight(1f),
                    singleLine = true
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Auto-split trip expenses", fontWeight = FontWeight.Medium, fontSize = 14.sp)
                    Text("Automatically tag expenses during trip dates to this trip", fontSize = 12.sp, color = InkSoft)
                }
                Checkbox(
                    checked = autoSplit,
                    onCheckedChange = { autoSplit = it }
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    onSave(name.ifEmpty { "New $kind" }, kind, selectedMembers.toList(), autoSplit)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
            ) {
                Text("Create ${kind.replaceFirstChar { it.uppercase() }}", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Cream)
            }
        }
    }
}
