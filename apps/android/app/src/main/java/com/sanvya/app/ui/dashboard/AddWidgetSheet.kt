package com.sanvya.app.ui.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaText

/**
 * Web's "Add a widget" modal.
 *
 * **It only offers tiles that are built.** Web can list all fourteen because
 * all fourteen render; here `TileId.isBuilt` gates the list, so a user can
 * never add a tile that would appear as an empty card. The eleven unbuilt ones
 * are absent from the picker, not present-and-broken, and are tracked in
 * ABSENT-BY-DECISION.md.
 *
 * A premium tile the user is not entitled to is shown **locked rather than
 * hidden**, which is web's behaviour: knowing the feature exists is the point
 * of the lock. It is only ever a locked row here, never a locked tile on the
 * dashboard — those are filtered out of the grid entirely.
 */
@Composable
fun AddWidgetSheet(
    open: Boolean,
    isPaid: Boolean,
    onClose: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val enabled by DashboardPrefs.ids.collectAsState()
    val available = TileId.entries.filter { it.isBuilt && it !in enabled }

    SanvyaModal(open = open, onClose = onClose, label = S.Dashboard.addWidget(sRes())) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(bottom = 12.dp)) {
            SanvyaText(S.Dashboard.addWidget(sRes()), style = SanvyaType.h2)
            SanvyaText(
                S.Dashboard.addWidgetIntro(sRes()),
                style = SanvyaType.statLabel,
                color = colors.text2,
            )
        }

        if (available.isEmpty()) {
            SanvyaText(S.Dashboard.allAdded(sRes()), style = SanvyaType.statLabel, color = colors.text2)
        } else {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.verticalScroll(rememberScrollState()),
            ) {
                available.forEach { tile ->
                    val locked = tile.isPremium && !isPaid
                    SanvyaCard(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Column(Modifier.weight(1f)) {
                                SanvyaText(
                                    tile.title(sRes()),
                                    style = SanvyaType.body,
                                    color = if (locked) colors.text2 else colors.text,
                                )
                                if (locked) {
                                    SanvyaText(
                                        S.Dashboard.premium(sRes()),
                                        style = SanvyaType.statLabel,
                                        color = colors.text2,
                                    )
                                }
                            }
                            SanvyaButton(
                                onClick = { DashboardPrefs.setEnabled(tile, true) },
                                enabled = !locked,
                            ) {
                                SanvyaText(S.Translation.commonAdd(sRes()), style = SanvyaType.button)
                            }
                        }
                    }
                }
            }
        }

        if (!isPaid) {
            SanvyaText(
                S.Dashboard.premiumNote(sRes()),
                style = SanvyaType.statLabel,
                color = colors.text2,
                modifier = Modifier.padding(top = 10.dp),
            )
        }

        Row(modifier = Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.End) {
            SanvyaButton(onClick = onClose) {
                SanvyaText(S.Translation.commonDone(sRes()), style = SanvyaType.button)
            }
        }
    }
}
