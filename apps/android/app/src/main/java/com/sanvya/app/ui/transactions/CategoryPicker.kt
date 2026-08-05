package com.sanvya.app.ui.transactions

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenu
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.sanvya.app.data.repository.CategoryRow

/** Category picker shared by Create/EditTransactionScreen — a plain
 * dropdown of relevant categories (flat, "Parent › Child" for children),
 * a faithful-logic (not pixel-identical widget) port of `SearchSelect`
 * per docs/mobile/screen-specs/transactions.md's New section note. Kept in
 * its own file per the Phase B "component reuse" rule — both screens need
 * this, and Accounts already caught one inline-duplication violation this
 * session, don't repeat it here. */
@Composable
fun CategoryPicker(
    categories: List<CategoryRow>,
    selectedId: String?,
    onSelect: (String?) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val roots = categories.filter { it.parentId == null }
    val label = categories.find { it.id == selectedId }?.let { cat ->
        val parent = categories.find { it.id == cat.parentId }
        if (parent != null) "${parent.name} › ${cat.name}" else cat.name
    } ?: "Uncategorised"

    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = label,
            onValueChange = {},
            readOnly = true,
            modifier = Modifier.fillMaxWidth().menuAnchor(),
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("Uncategorised") }, onClick = { onSelect(null); expanded = false })
            roots.forEach { parent ->
                DropdownMenuItem(text = { Text(parent.name) }, onClick = { onSelect(parent.id); expanded = false })
                categories.filter { it.parentId == parent.id }.forEach { child ->
                    DropdownMenuItem(
                        text = { Text("  ${parent.name} › ${child.name}") },
                        onClick = { onSelect(child.id); expanded = false },
                    )
                }
            }
        }
    }
}
