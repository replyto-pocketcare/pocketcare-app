package com.sanvya.app.ui.splits

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.data.repository.PendingSettlement
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.accounts.ChipRow
import com.sanvya.app.ui.components.Muted
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.ui.formatMoney

/**
 * Payments other people say they have made to you, awaiting your confirmation
 * -- ported from `apps/web/src/payments/PendingSettlements.tsx`.
 *
 * **This exists because UPI Intent gives us no callback.** The payer told their
 * bank, not us. Only the payee can see the money land, so only the payee can
 * close the loop. Without this screen a UPI settlement raised on a phone stayed
 * pending until somebody opened the browser -- and both people's balances
 * stayed wrong in the meantime.
 *
 * Note what "Didn't arrive" does NOT do: it does not unwind the payer's ledger
 * entry. The ledger is append-only, and if their money really left, that is
 * still true. What changes is that the settlement stops counting toward the
 * balance between you. Web's own comment, and the reason the two buttons are
 * not mirror images.
 *
 * Renders nothing when there is nothing pending -- web returns null, and an
 * empty "Confirm a payment" card would be a permanent piece of furniture asking
 * about money nobody sent.
 *
 * Mirrors iOS's PendingSettlementsCard.swift.
 */
@Composable
fun PendingSettlementsCard(viewModel: SplitsViewModel) {
    val res = sRes()
    val pending by viewModel.pending.collectAsState()
    val accounts by viewModel.accounts.collectAsState()
    val busyId by viewModel.busySettlementId.collectAsState()

    if (pending.isEmpty()) return

    // ONE picker for the card, not one per row -- web keeps a single
    // `accountId` in page state and every row reads it. Confirming three
    // payments that all landed in the same account should not mean choosing
    // that account three times.
    var accountId by remember { mutableStateOf("") }

    SanvyaCard(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SanvyaText(
                    S.Payments.confirmTitle(res),
                    SanvyaType.body.copy(fontWeight = FontWeight.SemiBold),
                )
                Muted(S.Payments.confirmIntro(res), style = SanvyaType.body.copy(fontSize = 13.sp))
            }

            pending.forEach { settlement ->
                PendingSettlementRow(
                    settlement = settlement,
                    name = viewModel.nameOfUser(settlement.fromUser, res),
                    busy = busyId == settlement.id,
                    anyBusy = busyId != null,
                    accountOptions = accounts.map { it.id },
                    accountLabel = { id -> accounts.find { it.id == id }?.name ?: "" },
                    accountId = accountId,
                    onAccountChange = { accountId = it },
                    onArrived = { viewModel.confirmArrived(settlement, accountId.ifEmpty { null }) },
                    onDidNotArrive = { viewModel.markDidNotArrive(settlement) },
                )
            }
        }
    }
}

@Composable
private fun PendingSettlementRow(
    settlement: PendingSettlement,
    name: String,
    busy: Boolean,
    anyBusy: Boolean,
    accountOptions: List<String>,
    accountLabel: (String) -> String,
    accountId: String,
    onAccountChange: (String) -> Unit,
    onArrived: () -> Unit,
    onDidNotArrive: () -> Unit,
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current

    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SanvyaText(
                S.Payments.confirmClaim(res, name),
                SanvyaType.body.copy(fontSize = 14.sp),
                modifier = Modifier.weight(1f),
            )
            SanvyaText(
                formatMoney(settlement.amount, settlement.currency),
                SanvyaType.body.copy(fontWeight = FontWeight.Bold),
            )
        }

        // The UPI reference is the one thread tying this to a line in a bank
        // statement, which is exactly what you need when the money is missing.
        settlement.upiRef?.takeIf { it.isNotBlank() }?.let { ref ->
            Muted(S.Payments.confirmReference(res, ref), style = SanvyaType.body.copy(fontSize = 11.5.sp))
        }

        Muted(S.Payments.confirmReceivedInto(res), style = SanvyaType.body.copy(fontSize = 12.sp))
        // "" is a real option, not a placeholder: web's empty `<option>` means
        // "don't record a deposit", for money that arrived somewhere this app
        // does not track.
        ChipRow(
            options = listOf("") + accountOptions,
            selected = accountId,
            label = { id -> if (id.isEmpty()) S.Payments.confirmNoAccount(res) else accountLabel(id) },
            onSelect = onAccountChange,
            colors = colors,
        )

        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onArrived, enabled = !anyBusy) {
                Text(if (busy) S.Translation.commonSaving(res) else S.Payments.confirmYes(res))
            }
            OutlinedButton(onClick = onDidNotArrive, enabled = !anyBusy) {
                Text(S.Payments.confirmNo(res))
            }
        }
    }
}
