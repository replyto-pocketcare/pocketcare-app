package com.sanvya.app.ui.splits

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.res.Resources
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.splits.InviteOutcome
import com.sanvya.app.domain.splits.Invitee
import com.sanvya.app.domain.splits.inviteeKey
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.Muted
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaChip
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.components.SanvyaText

/**
 * Inviting people to a group -- ported from the invite modal in
 * `apps/web/app/groups/[id]/page.tsx`.
 *
 * **This was the single biggest thing a native user could not do.** Neither
 * platform could add anyone to a group who was not already a connection, so a
 * native user could create a group and then not fill it. Every other split
 * feature sits downstream of having members.
 *
 * Two paths, both web's:
 *
 *  * **Pick people.** Search existing connections, or type an address that is
 *    not one yet; each becomes a chip. Inviting loops one call per chip,
 *    because the Edge Function takes a single address -- and a bounce on one
 *    address still adds the other three.
 *  * **Share a link.** No recipient at all. The server returns the URL; this
 *    app does NOT build one from the token, because unlike a browser it has no
 *    origin to build it from, and inventing a host would produce a link that
 *    silently goes nowhere.
 *
 * Which one you get for a typed address is the server's call, not this
 * screen's: a registered user is added outright, anyone else produces a link.
 * The summary line says which happened, because they are different news.
 *
 * Mirrors iOS's InviteSheet.swift.
 */
@Composable
fun InviteSheet(
    open: Boolean,
    groupName: String,
    viewModel: GroupDetailViewModel,
    onClose: () -> Unit,
) {
    if (!open) return
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current

    val query by viewModel.inviteQuery.collectAsState()
    val selected by viewModel.selected.collectAsState()
    val suggestions by viewModel.suggestions.collectAsState()
    val inviting by viewModel.inviting.collectAsState()
    val outcome by viewModel.inviteOutcome.collectAsState()
    val link by viewModel.inviteLink.collectAsState()
    val error by viewModel.inviteError.collectAsState()
    var copied by remember { mutableStateOf(false) }

    // Web clears the panel every time the modal opens, so a previous run's
    // link and summary are never mistaken for this one's.
    LaunchedEffect(Unit) { viewModel.resetInvite() }
    LaunchedEffect(link) { copied = false }

    SanvyaModal(open = true, onClose = { onClose(); viewModel.resetInvite() }) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SanvyaText(S.Groups.inviteTo(res, groupName), SanvyaType.h2)
            Muted(S.Groups.inviteBody(res), style = SanvyaType.body.copy(fontSize = 13.sp))

            if (selected.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    selected.forEach { invitee ->
                        InviteeChip(
                            label = invitee.name.ifEmpty { invitee.email },
                            removeLabel = S.Groups.remove(res),
                            onRemove = { viewModel.removeInvitee(inviteeKey(invitee)) },
                        )
                    }
                }
            }

            SanvyaInput(
                value = query,
                onValueChange = viewModel::setInviteQuery,
                placeholder = S.Groups.invitePlaceholder(res),
            )

            if (suggestions.suggestions.isNotEmpty() || suggestions.canAddTypedEmail) {
                SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(4.dp)) {
                    suggestions.suggestions.forEach { candidate ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(SanvyaShape.radiusSm)
                                .clickable { viewModel.addInvitee(candidate) }
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            SanvyaText(
                                candidate.name,
                                SanvyaType.body.copy(fontWeight = FontWeight.Medium),
                                modifier = Modifier.weight(1f),
                            )
                            SanvyaText(
                                candidate.email,
                                SanvyaType.body.copy(fontSize = 12.sp),
                                color = colors.text2,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                    if (suggestions.canAddTypedEmail) {
                        val typed = query.trim()
                        SanvyaText(
                            S.Groups.inviteAddEmail(res, typed),
                            SanvyaType.body,
                            color = colors.accent,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(SanvyaShape.radiusSm)
                                // The typed address becomes BOTH the name and
                                // the address, as web does -- there is nothing
                                // else to call someone who is not a user yet.
                                .clickable { viewModel.addInvitee(Invitee(null, typed, typed)) }
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                        )
                    }
                    if (suggestions.moreMatches > 0) {
                        Muted(
                            S.Groups.inviteNarrow(res, suggestions.moreMatches),
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                            style = SanvyaType.body.copy(fontSize = 12.sp),
                        )
                    }
                }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SanvyaButton(
                    onClick = { viewModel.inviteSelected() },
                    enabled = !inviting && selected.isNotEmpty(),
                ) {
                    SanvyaText(
                        if (selected.isEmpty()) {
                            S.Groups.invite(res)
                        } else {
                            S.Groups.inviteCount(res, count = selected.size)
                        },
                        SanvyaType.button,
                        color = Color.White,
                    )
                }
                SanvyaChip(
                    S.Groups.orShareLink(res),
                    active = false,
                    onClick = { viewModel.createShareLink() },
                )
            }

            outcome?.takeIf { !it.isEmpty }?.let { result ->
                SanvyaCard(
                    modifier = Modifier.fillMaxWidth(),
                    padding = PaddingValues(10.dp),
                    background = colors.surface2,
                ) {
                    SanvyaText(outcomeText(res, result), SanvyaType.body.copy(fontSize = 13.sp))
                }
            }

            error?.let {
                SanvyaText(
                    S.Groups.error(res, it),
                    SanvyaType.body.copy(fontSize = 13.sp),
                    color = colors.negative,
                )
            }

            link?.let { url ->
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    // Read-only, and selectable rather than editable: the link
                    // is the server's and there is nothing to edit in it.
                    SanvyaInput(value = url, onValueChange = {}, enabled = false)
                    SanvyaButton(
                        onClick = {
                            copyToClipboard(context, url)
                            copied = true
                        },
                        modifier = Modifier.align(Alignment.End),
                    ) {
                        SanvyaText(
                            if (copied) S.Groups.copied(res) else S.Groups.copyLink(res),
                            SanvyaType.button,
                            color = Color.White,
                        )
                    }
                }
            }
        }
    }
}

/** One picked invitee, with web's inline remove button. */
@Composable
private fun InviteeChip(label: String, removeLabel: String, onRemove: () -> Unit) {
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier
            .clip(SanvyaShape.pill)
            .background(colors.accentGhost)
            .padding(start = 10.dp, top = 3.dp, bottom = 3.dp, end = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SanvyaText(label, SanvyaType.body.copy(fontSize = 13.sp))
        Box(
            modifier = Modifier
                .size(18.dp)
                .clip(SanvyaShape.pill)
                .background(colors.surface2)
                .clickable(onClick = onRemove),
            contentAlignment = Alignment.Center,
        ) {
            SanvyaText(
                "×",
                SanvyaType.body.copy(fontSize = 13.sp),
                color = colors.text2,
            )
        }
    }
}

/**
 * Web's summary line: the three counts, joined by " · ", omitting the zeroes.
 *
 * The split is what the user needs: "added" means they are in the group now,
 * "invite link created" means an address that is not a Sanvya account yet and
 * somebody has to send the link on.
 */
private fun outcomeText(res: Resources, outcome: InviteOutcome): String {
    val parts = buildList {
        if (outcome.added > 0) add(S.Groups.invitedAdded(res, count = outcome.added))
        if (outcome.links > 0) add(S.Groups.invitedLinks(res, count = outcome.links))
        if (outcome.failed.isNotEmpty()) {
            add(S.Groups.invitedFailed(res, outcome.failed.joinToString(", ")))
        }
    }
    return parts.joinToString(" · ")
}

private fun copyToClipboard(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    clipboard?.setPrimaryClip(ClipData.newPlainText("invite", text))
}
