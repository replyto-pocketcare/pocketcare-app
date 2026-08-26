package com.sanvya.app.ui.taxonomy

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.LabelRow
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.components.ColorSwatchRow
import com.sanvya.app.ui.components.ConfirmDialog
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.parseHexColor

/** Manage labels -- ported from apps/web/app/settings/labels/page.tsx. */
@Composable
fun LabelsScreen(viewModel: LabelsViewModel = viewModel()) {
    val labels by viewModel.labels.collectAsState()
    val search by viewModel.search.collectAsState()
    val newName by viewModel.newName.collectAsState()
    val newColor by viewModel.newColor.collectAsState()
    val colors = LocalSanvyaColors.current

    var editingId by remember { mutableStateOf<String?>(null) }
    var editingName by remember { mutableStateOf("") }
    var editingColor by remember { mutableStateOf(LabelsViewModel.DEFAULT_COLOR) }
    var pendingDelete by remember { mutableStateOf<LabelRow?>(null) }

    SanvyaPage(
        title = S.Labels.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        SanvyaCard(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            padding = PaddingValues(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = search,
                    onValueChange = viewModel::setSearch,
                    placeholder = { Text(S.Labels.searchPlaceholder(sRes())) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )

                if (labels.isEmpty()) {
                    Text(S.Labels.noLabels(sRes()), fontSize = 13.sp, color = colors.text2)
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        labels.forEach { label ->
                            if (editingId == label.id) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                                        .padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    OutlinedTextField(
                                        value = editingName,
                                        onValueChange = { editingName = it },
                                        singleLine = true,
                                        modifier = Modifier.fillMaxWidth(),
                                    )
                                    ColorSwatchRow(selected = editingColor) { editingColor = it }
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        TaxonomyChip(S.Labels.save(sRes()), false, colors) {
                                            viewModel.save(label.id, editingName, editingColor)
                                            editingId = null
                                        }
                                        TaxonomyChip(S.Labels.cancel(sRes()), false, colors) {
                                            editingId = null
                                        }
                                    }
                                }
                            } else {
                                LabelRowCard(
                                    label = label,
                                    colors = colors,
                                    onEdit = {
                                        editingName = label.name
                                        editingColor = label.color ?: LabelsViewModel.DEFAULT_COLOR
                                        editingId = label.id
                                    },
                                    onDelete = { pendingDelete = label },
                                )
                            }
                        }
                    }
                }

                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = viewModel::setNewName,
                        placeholder = { Text(S.Labels.newLabel(sRes())) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    // The SAME swatch row the account form uses, not a free
                    // colour well. Web's `<input type="color">` has no Compose
                    // equivalent, and adopting a free picker on iOS alone would
                    // put the two platforms out of step over a control neither
                    // spec has settled -- the same call RecurringFormScreen made
                    // about dates. Recorded in PARITY_AUDIT.
                    ColorSwatchRow(selected = newColor) { viewModel.setNewColor(it) }
                    Button(onClick = viewModel::add, enabled = newName.isNotBlank()) {
                        Text(S.Labels.addLabel(sRes()))
                    }
                }
            }
        }
    }

    pendingDelete?.let { label ->
        ConfirmDialog(
            title = S.Labels.deleteTitle(sRes()),
            message = S.Labels.deleteMsg(sRes(), label.name),
            confirmLabel = S.Translation.commonDelete(sRes()),
            cancelLabel = S.Labels.cancel(sRes()),
            onConfirm = {
                viewModel.delete(label.id)
                pendingDelete = null
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun LabelRowCard(
    label: LabelRow,
    colors: SanvyaColors,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .border(1.dp, colors.border, RoundedCornerShape(8.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .size(14.dp)
                .background(parseHexColor(label.color ?: LabelsViewModel.DEFAULT_COLOR), CircleShape),
        )
        Text(
            label.name,
            fontWeight = FontWeight.Medium,
            fontSize = 14.sp,
            color = colors.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        TaxonomyChip(S.Labels.edit(sRes()), false, colors, onEdit)
        TaxonomyChip(S.Labels.delete(sRes()), false, colors, onDelete)
    }
}
