package com.sanvya.app.ui.accounts

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.theme.LocalSanvyaColors

/**
 * New account — ported from apps/web/app/accounts/new/page.tsx per
 * docs/mobile/screen-specs/accounts.md, regular-account path only (credit
 * card / demat branches explicitly deferred to those screens, see spec).
 */
@Composable
fun CreateAccountScreen(
    onBack: () -> Unit = {},
    onSaved: () -> Unit = {},
    viewModel: CreateAccountViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalSanvyaColors.current

    LaunchedEffect(uiState.savedAccountId) {
        if (uiState.savedAccountId != null) onSaved()
    }

    Scaffold(
        containerColor = colors.bg,
        topBar = {
            TopAppBar(
                title = { Text("New account", fontWeight = FontWeight.Bold, color = colors.text) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = colors.text2)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // Load-bearing copy, not decorative -- keep verbatim (spec).
            Text(
                "Nothing here connects to your bank. You're naming a place your money sits and typing in the amount yourself.",
                fontSize = 13.5.sp,
                color = colors.text2,
            )
            OutlinedTextField(
                value = uiState.name,
                onValueChange = viewModel::setName,
                label = { Text("Account name") },
                modifier = Modifier.fillMaxWidth(),
            )

            Text("Type", fontSize = 13.sp, color = colors.text2)
            ChipRow(
                options = ACCOUNT_TYPES,
                selected = uiState.type,
                label = { it.replace("_", " ").replaceFirstChar { c -> c.uppercase() } },
                onSelect = viewModel::setType,
                colors = colors,
            )

            Text("Currency", fontSize = 13.sp, color = colors.text2)
            ChipRow(
                options = ACCOUNT_CURRENCIES,
                selected = uiState.currency,
                label = { it },
                onSelect = viewModel::setCurrency,
                colors = colors,
            )

            Text("Colour", fontSize = 13.sp, color = colors.text2)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ACCOUNT_COLOR_HEX.forEach { hex ->
                    val selected = hex == uiState.color
                    Box(
                        modifier = Modifier
                            .size(30.dp)
                            .clip(CircleShape)
                            .background(parseHexColor(hex))
                            .border(if (selected) 3.dp else 2.dp, if (selected) colors.text else colors.border, CircleShape)
                            .clickable { viewModel.setColor(hex) },
                    )
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = uiState.includeInNetWorth, onCheckedChange = viewModel::setIncludeInNetWorth)
                Text("Include in net worth", fontSize = 14.sp, color = colors.text)
            }

            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Checkbox(checked = uiState.allowNegativeEffective, onCheckedChange = viewModel::setAllowNegative)
                Column {
                    Text("Allow negative balance", fontSize = 14.sp, color = colors.text)
                    Text(
                        if (uiState.allowNegativeEffective) "This account can go below zero without a warning."
                        else "You'll be warned before this account would go below zero.",
                        fontSize = 12.sp,
                        color = colors.text2,
                    )
                }
            }

            OutlinedTextField(
                value = uiState.openingBalance,
                onValueChange = { v -> viewModel.setOpeningBalance(v.filter { it.isDigit() || it == '.' || it == '-' }) },
                label = { Text("Opening balance (${uiState.currency})") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                modifier = Modifier.fillMaxWidth(),
            )

            Button(
                onClick = { viewModel.save() },
                enabled = uiState.name.isNotBlank() && !uiState.saving,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            ) {
                Text(if (uiState.saving) "Saving…" else "Save")
            }
        }
    }
}

@Composable
internal fun <T> ChipRow(
    options: List<T>,
    selected: T,
    label: (T) -> String,
    onSelect: (T) -> Unit,
    colors: com.sanvya.app.theme.SanvyaColors,
) {
    androidx.compose.foundation.layout.FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEach { opt ->
            val isSelected = opt == selected
            AssistChip(
                onClick = { onSelect(opt) },
                label = { Text(label(opt), fontSize = 13.sp) },
                colors = AssistChipDefaults.assistChipColors(
                    containerColor = if (isSelected) colors.accent else colors.surface,
                    labelColor = if (isSelected) Color.White else colors.text,
                ),
            )
        }
    }
}

private fun parseHexColor(hex: String): Color {
    return try {
        Color(android.graphics.Color.parseColor(hex))
    } catch (e: IllegalArgumentException) {
        Color.Gray
    }
}
