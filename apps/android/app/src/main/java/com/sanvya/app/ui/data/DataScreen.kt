package com.sanvya.app.ui.data

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.csv.IMPORT_ADAPTERS
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.baseCurrencyNow
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.isoLabel

/**
 * Import & export -- ported from apps/web/app/data/page.tsx.
 *
 * **The file halves are the Storage Access Framework**: `CreateDocument` for the
 * export and `OpenDocument` for the import, where web uses an anchor download
 * and an `<input type="file">`. There is no shared shape to port here; what IS
 * shared is everything either side of the picker, which is domain's and the
 * repository's.
 *
 * SAF specifically, not a WRITE_EXTERNAL_STORAGE path: the user picks the
 * destination, the app needs no storage permission at all, and the file can
 * land in Drive or on a USB stick as easily as in Downloads.
 */
@Composable
fun DataScreen(viewModel: DataViewModel = viewModel()) {
    val state by viewModel.state.collectAsState()
    val adapterId by viewModel.adapterId.collectAsState()
    val skipDuplicates by viewModel.skipDuplicates.collectAsState()
    val pendingExport by viewModel.pendingExport.collectAsState()
    val isPaidUser by viewModel.isPaidUser.collectAsState()
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current

    val createDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri: Uri? ->
        val csv = pendingExport?.csv
        if (uri != null && csv != null) {
            runCatching {
                context.contentResolver.openOutputStream(uri)?.use { it.write(csv.toByteArray()) }
            }
        }
        viewModel.consumePendingExport()
    }

    // Hoisted OUT of the launcher callbacks: `sRes()` is @Composable and cannot
    // be called from one. Kotlin's error for that names the lambda, not the
    // string, and reads like a scope problem rather than a rule.
    val res = sRes()
    val readFailBlank = S.Data.readFail(res, "")
    val noRowsMessage = S.Data.noRows(res)
    val noExportMessage = S.Data.noExport(res)

    val openDocument = rememberLauncherForActivityResult(
        // `*/*` alongside the CSV types: plenty of banks hand out a .csv the
        // system types as application/octet-stream, and a picker that greys out
        // the file the user came to import is a dead end.
        ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val name = uri.lastPathSegment?.substringAfterLast('/') ?: "import.csv"
        runCatching {
            context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
        }.onSuccess { text ->
            if (text == null) {
                viewModel.failedToRead(readFailBlank)
            } else {
                viewModel.parse(name, text, noRowsMessage)
            }
        }.onFailure { e ->
            viewModel.failedToRead(S.Data.readFail(res, e.message ?: e.toString()))
        }
    }

    // Launching the SAF picker is a side effect of the CSV becoming ready, not
    // of a tap: the export query is async, and the picker must not open before
    // there is anything to write into it.
    LaunchedEffect(pendingExport) {
        if (pendingExport != null) createDocument.launch(pendingExport!!.suggestedName)
    }

    SanvyaPage(
        title = S.Data.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(S.Data.introPre(sRes()), fontSize = 13.sp, color = colors.text2)

            // ---- Export ----
            SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(20.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(S.Data.export(sRes()), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                    Text(S.Data.exportNote(sRes()), fontSize = 13.sp, color = colors.text2)
                    Button(
                        onClick = {
                            viewModel.exportCsv(
                                noExportMessage = noExportMessage,
                                failedMessage = { S.Data.exportFailed(res, it) },
                                exportedMessage = { S.Data.exported(res, it) },
                            )
                        },
                        enabled = !state.exporting,
                    ) {
                        Text(if (state.exporting) S.Data.preparing(sRes()) else S.Data.exportBtn(sRes()))
                    }
                    state.exportMessage?.let { Text(it, fontSize = 13.sp, color = colors.text2) }
                }
            }

            // ---- Import ----
            SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(20.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(S.Data.import(sRes()), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.text)
                    when (isPaidUser) {
                        // Nothing: the gate is closed but unexplained until the
                        // entitlement has actually been read.
                        null -> Unit
                        false -> Text(
                            S.Data.trialNote(sRes()),
                            fontSize = 14.sp,
                            color = colors.text,
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(colors.accentGhost, RoundedCornerShape(8.dp))
                                .padding(12.dp),
                        )
                        true -> ImportForm(
                            state = state,
                            adapterId = adapterId,
                            skipDuplicates = skipDuplicates,
                            colors = colors,
                            onAdapter = viewModel::setAdapterId,
                            onSkipDuplicates = viewModel::setSkipDuplicates,
                            onPickFile = { openDocument.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "*/*")) },
                            onImport = { viewModel.runImport(baseCurrencyNow()) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ImportForm(
    state: DataState,
    adapterId: String,
    skipDuplicates: Boolean,
    colors: SanvyaColors,
    onAdapter: (String) -> Unit,
    onSkipDuplicates: (Boolean) -> Unit,
    onPickFile: () -> Unit,
    onImport: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(S.Data.fileFormat(sRes()), fontSize = 13.sp, color = colors.text2)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IMPORT_ADAPTERS.forEach { adapter ->
                val selected = adapter.id == adapterId
                AssistChip(
                    onClick = { onAdapter(adapter.id) },
                    label = { Text(adapter.label, fontSize = 12.sp) },
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = if (selected) colors.accent else colors.surface2,
                        labelColor = if (selected) Color.White else colors.text,
                    ),
                )
            }
        }

        Text(S.Data.csvFile(sRes()), fontSize = 13.sp, color = colors.text2)
        Button(onClick = onPickFile) {
            Text(state.fileName ?: S.Data.csvFile(sRes()))
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = skipDuplicates, onCheckedChange = onSkipDuplicates)
            Text(S.Data.skipDup(sRes()), fontSize = 14.sp, color = colors.text)
        }

        state.parseError?.let { Text(it, fontSize = 13.sp, color = colors.negative) }

        state.parsedRows?.let { rows ->
            Text(
                S.Data.foundPreview(sRes(), rows.size, state.fileName ?: ""),
                fontSize = 14.sp,
                color = colors.text,
            )
            // Six rows, as web previews -- enough to see the columns landed in
            // the right places without pretending this is the ledger.
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                rows.take(6).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(isoLabel(row.date, "d MMM y"), fontSize = 12.sp, color = colors.text2, modifier = Modifier.width(92.dp))
                        Text(row.type, fontSize = 12.sp, color = colors.text2, modifier = Modifier.width(68.dp))
                        Text("${row.currency} ${row.amount}", fontSize = 12.sp, color = colors.text2, modifier = Modifier.weight(1f))
                        Text(row.account, fontSize = 12.sp, color = colors.text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            Button(onClick = onImport, enabled = !state.importing) {
                Text(if (state.importing) S.Data.importing(sRes()) else S.Data.importBtn(sRes(), rows.size))
            }
        }

        state.result?.let { result ->
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface2, RoundedCornerShape(8.dp))
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    S.Data.resultLine(sRes(), result.created, result.skipped, result.failed),
                    fontSize = 14.sp,
                    color = colors.text,
                )
                if (result.errors.isNotEmpty()) {
                    Text(
                        S.Data.firstIssues(sRes(), result.errors.take(3).joinToString("; ")),
                        fontSize = 12.sp,
                        color = colors.text2,
                    )
                }
            }
        }

        Text(S.Data.footerNote(sRes()), fontSize = 12.sp, color = colors.text2)
    }
}
