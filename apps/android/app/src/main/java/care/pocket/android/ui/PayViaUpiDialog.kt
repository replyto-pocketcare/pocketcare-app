package care.pocket.android.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
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
import care.pocket.android.theme.*
import care.pocket.domain.upi.buildIntentUrl
import care.pocket.domain.upi.IntentParams
import care.pocket.domain.upi.maskVpa

@Composable
fun PayViaUpiDialog(
    counterpartyName: String,
    vpa: String,
    amountMinor: Long,
    note: String = "PocketCare settle-up",
    onDismiss: () -> Unit = {},
    onPaid: (ref: String) => Unit = {}
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current

    var showFallback by remember { mutableStateOf(false) }
    var copiedNotice by remember { mutableStateOf<String?>(null) }

    val builtIntent = remember(vpa, amountMinor, note) {
        buildIntentUrl(
            IntentParams(
                vpa = vpa,
                name = counterpartyName,
                amountMinor = amountMinor,
                note = note
            )
        )
    }

    val maskedVpa = remember(vpa) { maskVpa(vpa) }
    val amountRupees = remember(amountMinor) { String.format("%.2f", amountMinor / 100.0) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text("Pay via UPI", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Text(
                    "Paying $counterpartyName ($maskedVpa)",
                    fontSize = 13.sp,
                    color = InkSoft
                )

                Text(
                    "₹$amountRupees",
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = Terracotta
                )

                Button(
                    onClick = {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(builtIntent.url))
                        try {
                            context.startActivity(intent)
                        } catch (_: Exception) {
                            showFallback = true
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Terracotta)
                ) {
                    Text("Open UPI App", fontWeight = FontWeight.Bold, color = Cream)
                }

                if (!showFallback) {
                    TextButton(
                        onClick = { showFallback = true },
                        modifier = Modifier.align(Alignment.CenterHorizontally)
                    ) {
                        Text("Didn't open? Pay another way", fontSize = 12.sp, color = InkSoft)
                    }
                }

                if (showFallback) {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(containerColor = Clay100)
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text("Pay manually", fontWeight = FontWeight.Bold, fontSize = 13.sp)

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(vpa, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                                Button(
                                    onClick = {
                                        clipboard.setText(AnnotatedString(vpa))
                                        copiedNotice = "Copied UPI ID"
                                    },
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
                                ) {
                                    Text("Copy ID", fontSize = 11.sp)
                                }
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text("₹$amountRupees", fontSize = 12.sp, fontWeight = FontWeight.Medium)
                                Button(
                                    onClick = {
                                        clipboard.setText(AnnotatedString(amountRupees))
                                        copiedNotice = "Copied Amount"
                                    },
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp)
                                ) {
                                    Text("Copy Amount", fontSize = 11.sp)
                                }
                            }

                            copiedNotice?.let { notice ->
                                Text(notice, fontSize = 11.sp, color = Sage, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(4.dp))

                Button(
                    onClick = { onPaid(builtIntent.reference) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Sage)
                ) {
                    Text("I've paid — tell them", fontWeight = FontWeight.Bold, color = Cream)
                }

                Text(
                    "We can't see UPI payments directly, so we'll ask $counterpartyName to confirm it arrived.",
                    fontSize = 11.sp,
                    color = InkSoft
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = InkSoft)
            }
        }
    )
}
