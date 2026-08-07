package com.sanvya.app.ui.splits

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.upi.IntentParams
import com.sanvya.app.domain.upi.buildIntentUrl
import com.sanvya.app.domain.upi.maskVpa
import com.sanvya.app.theme.LocalSanvyaColors

/**
 * Android mirror of the already-real `PayViaUpiSheet.swift` (task #30) --
 * that file existed and worked before this pass, this is the Android
 * equivalent that never did. Same structure: open the UPI app via an
 * Intent, fall back to copy-the-details if it doesn't, "I've paid — tell
 * them" since a UPI Intent hand-off has no success callback (see
 * PayViaUpi.tsx's own doc comment, quoted in the iOS file).
 */
@Composable
fun PayViaUpiDialog(
    counterpartyName: String,
    vpa: String,
    amountMinor: Long,
    note: String = "Sanvya settle-up",
    onDismiss: () -> Unit,
    onPaid: (ref: String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var showFallback by remember { mutableStateOf(false) }
    var copiedNotice by remember { mutableStateOf<String?>(null) }

    val built = remember(vpa, amountMinor, note) {
        runCatching { buildIntentUrl(IntentParams(vpa = vpa, name = counterpartyName, amountMinor = amountMinor.toDouble(), note = note)) }.getOrNull()
    }
    val amountRupees = String.format("%.2f", amountMinor / 100.0)

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.surface,
        title = { Text("Pay via UPI", fontWeight = FontWeight.Bold, color = colors.text) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth()) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Paying $counterpartyName", fontWeight = FontWeight.SemiBold, color = colors.text)
                    Text(maskVpa(vpa), fontSize = 12.sp, color = colors.text2)
                }
                Text("₹$amountRupees", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = colors.accent)

                Button(
                    onClick = {
                        val url = built?.url
                        if (url != null) {
                            try {
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            } catch (e: ActivityNotFoundException) {
                                showFallback = true
                            }
                        } else {
                            showFallback = true
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Open UPI App") }

                if (!showFallback) {
                    TextButton(onClick = { showFallback = true }) { Text("Didn't open? Pay another way", fontSize = 12.sp, color = colors.text2) }
                }

                if (showFallback) {
                    Column(
                        modifier = Modifier.fillMaxWidth().background(colors.surface2, MaterialTheme.shapes.medium).padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Pay manually", fontWeight = FontWeight.SemiBold, fontSize = 13.sp, color = colors.text)
                        CopyRow(vpa, "Copy ID") { clipboard.setText(AnnotatedString(vpa)); copiedNotice = "Copied UPI ID" }
                        CopyRow("₹$amountRupees", "Copy Amount") { clipboard.setText(AnnotatedString(amountRupees)); copiedNotice = "Copied Amount" }
                        copiedNotice?.let { Text(it, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = colors.positive) }
                    }
                }

                Button(
                    onClick = { built?.let { onPaid(it.ref) } },
                    colors = ButtonDefaults.buttonColors(containerColor = colors.positive),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("I've paid — tell them") }

                Text(
                    "We can't see UPI payments directly, so we'll ask $counterpartyName to confirm it arrived.",
                    fontSize = 11.sp, color = colors.text2, modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel", color = colors.text2) } },
    )
}

@Composable
private fun CopyRow(value: String, label: String, onCopy: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(value, fontSize = 12.sp)
        TextButton(onClick = onCopy) { Text(label, fontSize = 11.sp) }
    }
}
