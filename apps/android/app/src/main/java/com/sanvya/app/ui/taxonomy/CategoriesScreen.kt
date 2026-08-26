package com.sanvya.app.ui.taxonomy

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.taxonomy.TaxonomyCategory
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.components.ConfirmDialog
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage

/**
 * Manage categories -- ported from apps/web/app/settings/categories/page.tsx.
 *
 * Reached from Settings, as on web. The tree is domain's, vector-tested; this
 * file is the rows, the inline rename and the add row.
 */
@Composable
fun CategoriesScreen(viewModel: CategoriesViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    val search by viewModel.search.collectAsState()
    val newName by viewModel.newName.collectAsState()
    val newKind by viewModel.newKind.collectAsState()
    val newParentId by viewModel.newParentId.collectAsState()
    val colors = LocalSanvyaColors.current

    var editingId by remember { mutableStateOf<String?>(null) }
    var editingName by remember { mutableStateOf("") }
    var pendingDelete by remember { mutableStateOf<TaxonomyCategory?>(null) }

    SanvyaPage(
        title = S.Categories.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        SanvyaCard(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            padding = PaddingValues(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    value = search,
                    onValueChange = viewModel::setSearch,
                    placeholder = { Text(S.Categories.searchPlaceholder(sRes())) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )

                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    state.nodes.forEach { node ->
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                // The disclosure control is a plain +/- box on
                                // web, not a chevron; keeping the glyph keeps
                                // the two platforms and the browser saying the
                                // same thing.
                                Box(
                                    modifier = Modifier
                                        .size(24.dp)
                                        .border(1.dp, colors.border, RoundedCornerShape(7.dp))
                                        .background(colors.surface, RoundedCornerShape(7.dp))
                                        .clickable { viewModel.toggle(node.category.id) },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        if (node.isOpen) "−" else "+",
                                        fontSize = 13.sp,
                                        color = colors.text2,
                                    )
                                }
                                CategoryRow(
                                    category = node.category,
                                    childCount = node.childCount,
                                    indent = false,
                                    colors = colors,
                                    isEditing = editingId == node.category.id,
                                    editingName = editingName,
                                    onEditingNameChange = { editingName = it },
                                    onStartEdit = {
                                        editingName = node.category.name
                                        editingId = node.category.id
                                    },
                                    onSave = {
                                        viewModel.rename(node.category.id, editingName)
                                        editingId = null
                                    },
                                    onCancel = { editingId = null },
                                    onDelete = { pendingDelete = node.category },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            if (node.isOpen) {
                                node.children.forEach { child ->
                                    CategoryRow(
                                        category = child,
                                        childCount = null,
                                        indent = true,
                                        colors = colors,
                                        isEditing = editingId == child.id,
                                        editingName = editingName,
                                        onEditingNameChange = { editingName = it },
                                        onStartEdit = {
                                            editingName = child.name
                                            editingId = child.id
                                        },
                                        onSave = {
                                            viewModel.rename(child.id, editingName)
                                            editingId = null
                                        },
                                        onCancel = { editingId = null },
                                        onDelete = { pendingDelete = child },
                                    )
                                }
                            }
                        }
                    }
                }

                OutlinedTextField(
                    value = newName,
                    onValueChange = viewModel::setNewName,
                    placeholder = { Text(S.Categories.newCategory(sRes())) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TaxonomyChip(S.Categories.expense(sRes()), newKind == "expense", colors) {
                        viewModel.setNewKind("expense")
                    }
                    TaxonomyChip(S.Categories.income(sRes()), newKind == "income", colors) {
                        viewModel.setNewKind("income")
                    }
                }
                // Chips, not a dropdown -- the same choice RecurringFormScreen
                // makes, and web's own `<select>` has exactly this shape: an
                // empty first option meaning "top level", then one per
                // top-level category of the kind being added.
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    TaxonomyChip(S.Categories.topLevel(sRes()), newParentId.isEmpty(), colors) {
                        viewModel.setNewParentId("")
                    }
                    state.parentOptions.forEach { option ->
                        TaxonomyChip(
                            S.Categories.under(sRes(), option.name),
                            newParentId == option.id,
                            colors,
                        ) { viewModel.setNewParentId(option.id) }
                    }
                }
                Button(onClick = viewModel::add, enabled = newName.isNotBlank()) {
                    Text(S.Categories.add(sRes()))
                }
            }
        }
    }

    pendingDelete?.let { category ->
        ConfirmDialog(
            title = S.Categories.deleteTitle(sRes()),
            message = S.Categories.deleteMsg(sRes(), category.name),
            confirmLabel = S.Translation.commonDelete(sRes()),
            cancelLabel = S.Categories.cancel(sRes()),
            onConfirm = {
                viewModel.delete(category.id)
                pendingDelete = null
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun CategoryRow(
    category: TaxonomyCategory,
    childCount: Int?,
    indent: Boolean,
    colors: SanvyaColors,
    isEditing: Boolean,
    editingName: String,
    onEditingNameChange: (String) -> Unit,
    onStartEdit: () -> Unit,
    onSave: () -> Unit,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (isEditing) {
        Row(
            modifier = modifier.padding(start = if (indent) 26.dp else 0.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = editingName,
                onValueChange = onEditingNameChange,
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            TaxonomyChip(S.Categories.save(sRes()), false, colors, onSave)
            TaxonomyChip(S.Categories.cancel(sRes()), false, colors, onCancel)
        }
        return
    }

    val kindLabel = if (category.kind == "income") {
        S.Categories.kindIncome(sRes())
    } else {
        S.Categories.kindExpense(sRes())
    }
    Row(
        modifier = modifier
            .padding(start = if (indent) 26.dp else 0.dp)
            .then(
                if (indent) Modifier else Modifier.border(1.dp, colors.border, RoundedCornerShape(8.dp))
            )
            .padding(horizontal = 10.dp, vertical = if (indent) 5.dp else 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            if (indent) "↳ ${category.name}" else category.name,
            fontSize = if (indent) 13.sp else 14.sp,
            color = if (indent) colors.text2 else colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        if (!indent) {
            Text(
                kindLabel + (childCount?.takeIf { it > 0 }?.let { " · $it" } ?: ""),
                fontSize = 11.sp,
                color = colors.text2,
            )
        }
        Spacer(Modifier.weight(1f))
        TaxonomyChip(S.Categories.edit(sRes()), false, colors, onStartEdit)
        TaxonomyChip("×", false, colors, onDelete)
    }
}

@Composable
internal fun TaxonomyChip(
    label: String,
    selected: Boolean,
    colors: SanvyaColors,
    onClick: () -> Unit,
) {
    AssistChip(
        onClick = onClick,
        label = { Text(label, fontSize = 12.sp) },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = if (selected) colors.accent else colors.surface2,
            labelColor = if (selected) Color.White else colors.text,
        ),
    )
}
