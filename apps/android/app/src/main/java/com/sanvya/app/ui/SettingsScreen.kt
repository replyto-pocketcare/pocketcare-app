package com.sanvya.app.ui

import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.Icons
import androidx.compose.foundation.clickable
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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onOpenDrawer: () -> Unit = {},
    onNavigateBack: () -> Unit = {},
    currentTier: String = "free",
    viewModel: SettingsViewModel = viewModel()
) {
    val scrollState = rememberScrollState()
    val amountsHidden by Prefs.amountsHidden.collectAsState()
    val notifPrefs by viewModel.notifPrefs.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onOpenDrawer) {
                        Icon(
                            imageVector = Icons.Default.Menu,
                            contentDescription = "Open Drawer"
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background)
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(scrollState)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Plan & Billing
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(12.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Plan & Billing", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurface)
                    Text("You're on the $currentTier plan.", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    
                    Spacer(modifier = Modifier.height(4.dp))
                    
                    Button(
                        onClick = { /* TODO: open billing */ },
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary),
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Text(if (currentTier == "free") "Upgrade to Premium" else "Manage Plan", fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.surface)
                    }
                }
            }

            // Preferences
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                shape = RoundedCornerShape(12.dp)
            ) {
                Column {
                    SettingsRow(title = "Currency", value = "INR") { /* TODO */ }
                    HorizontalDivider(color = MaterialTheme.colorScheme.background)
                    SettingsRow(title = "Language", value = "English") { /* TODO */ }
                    HorizontalDivider(color = MaterialTheme.colorScheme.background)
                    SettingsRow(title = "Theme", value = "System default") { /* TODO */ }
                }
            }

            // Privacy
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                shape = RoundedCornerShape(12.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Hide Amounts", fontWeight = FontWeight.Medium, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
                        Text("Mask balances and transaction amounts", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(
                        checked = amountsHidden,
                        onCheckedChange = { Prefs.setAmountsHidden(it) },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = MaterialTheme.colorScheme.surface,
                            checkedTrackColor = MaterialTheme.colorScheme.primary
                        )
                    )
                }
            }

            // Notifications
            if (notifPrefs != null) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(modifier = Modifier.padding(vertical = 8.dp)) {
                        Text(
                            text = "Notifications",
                            fontWeight = FontWeight.Bold,
                            fontSize = 16.sp,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                        )
                        Text(
                            text = "Get alerted about bills, budgets, low balances and unusual spend.",
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, bottom = 8.dp)
                        )
                        
                        NotificationToggleRow("Push notifications", notifPrefs!!.push_enabled == 1L) { v -> viewModel.updatePref { it.copy(push_enabled = if (v) 1 else 0) } }
                        NotificationToggleRow("Upcoming EMIs & bills", notifPrefs!!.emi_due == 1L) { v -> viewModel.updatePref { it.copy(emi_due = if (v) 1 else 0) } }
                        NotificationToggleRow("Budget limits", notifPrefs!!.budget == 1L) { v -> viewModel.updatePref { it.copy(budget = if (v) 1 else 0) } }
                        NotificationToggleRow("Low balance", notifPrefs!!.low_balance == 1L) { v -> viewModel.updatePref { it.copy(low_balance = if (v) 1 else 0) } }
                        NotificationToggleRow("Unusual transactions", notifPrefs!!.outlier == 1L) { v -> viewModel.updatePref { it.copy(outlier = if (v) 1 else 0) } }
                        
                        HorizontalDivider(color = MaterialTheme.colorScheme.background, modifier = Modifier.padding(vertical = 8.dp))
                        
                        Text(
                            text = "Groups & trips",
                            fontWeight = FontWeight.Bold,
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, bottom = 4.dp)
                        )
                        
                        NotificationToggleRow("Group activity", notifPrefs!!.group_invite == 1L) { v -> viewModel.updatePref { it.copy(group_invite = if (v) 1 else 0) } }
                        NotificationToggleRow("Shared expenses", notifPrefs!!.group_expense == 1L) { v -> viewModel.updatePref { it.copy(group_expense = if (v) 1 else 0) } }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsRow(title: String, value: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontWeight = FontWeight.Medium, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
        Text(value, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun NotificationToggleRow(title: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, fontWeight = FontWeight.Medium, fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurface)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = MaterialTheme.colorScheme.surface,
                checkedTrackColor = MaterialTheme.colorScheme.primary
            )
        )
    }
}
