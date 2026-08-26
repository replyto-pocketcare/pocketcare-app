package com.sanvya.app.ui.help

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.domain.help.HELP_SECTIONS
import com.sanvya.app.domain.help.HelpItem
import com.sanvya.app.domain.help.HelpSection
import com.sanvya.app.domain.help.filterHelp
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.parseHexColor

/**
 * Help & FAQ -- ported from apps/web/app/help/page.tsx.
 *
 * The CONTENT is generated from that file by tools/parity/generate-help.mjs,
 * so a change to web's copy reaches both native apps the next time the parity
 * job runs -- and fails the job if it has not. The filter is domain's,
 * vector-tested.
 *
 * It is English here because it is English on web: the FAQ is 33 string
 * literals in that component rather than keys in `packages/core/i18n`. The
 * chrome around it -- title, search box, no-match line, footer -- is translated.
 */
@Composable
fun HelpScreen() {
    var query by remember { mutableStateOf("") }
    var open by remember { mutableStateOf(emptySet<String>()) }
    val colors = LocalSanvyaColors.current
    val sections = filterHelp(HELP_SECTIONS, query)

    SanvyaPage(
        title = S.Help.title(sRes()),
        modifier = Modifier.verticalScroll(rememberScrollState()),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                S.Help.subtitlePre(sRes()) + S.Help.subtitleLink(sRes()) + S.Help.subtitlePost(sRes()),
                fontSize = 13.sp,
                color = colors.text2,
            )

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text(S.Help.searchPlaceholder(sRes())) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            if (sections.isEmpty()) {
                Text(S.Help.noMatch(sRes(), query), fontSize = 14.sp, color = colors.text2)
            }

            sections.forEach { section ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(
                            modifier = Modifier
                                .size(30.dp)
                                .background(parseHexColor(section.color), RoundedCornerShape(9.dp)),
                            contentAlignment = Alignment.Center,
                        ) {
                            SanvyaIcon(
                                // The generated content carries web's own icon
                                // name; an unknown one falls back to the help
                                // glyph rather than painting nothing -- though
                                // generate-help.mjs fails the parity job before
                                // one can reach here.
                                SanvyaIcons.byWebName[section.icon] ?: SanvyaIcons.help,
                                size = 17.dp,
                                tint = androidx.compose.ui.graphics.Color.White,
                            )
                        }
                        Text(
                            section.title,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = colors.text,
                        )
                    }
                    SanvyaCard(
                        modifier = Modifier.fillMaxWidth(),
                        padding = PaddingValues(6.dp),
                    ) {
                        section.items.forEach { item ->
                            HelpRow(
                                section = section,
                                item = item,
                                // Forced open while searching -- otherwise a
                                // match inside a collapsed answer would be
                                // invisible and the search would look broken.
                                // Web's `open.has(key) || !!q`, and the same
                                // rule categoryTree applies.
                                isOpen = open.contains(section.title + item.question) || query.isNotEmpty(),
                                onToggle = {
                                    val key = section.title + item.question
                                    open = if (key in open) open - key else open + key
                                },
                            )
                        }
                    }
                }
            }

            Text(
                S.Help.footer(sRes()),
                fontSize = 12.sp,
                color = colors.text2,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun HelpRow(
    section: HelpSection,
    item: HelpItem,
    isOpen: Boolean,
    onToggle: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val rotation by animateFloatAsState(if (isOpen) 90f else 0f, label = "help-chevron")
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onToggle)
                .padding(horizontal = 14.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                item.question,
                fontSize = 14.5.sp,
                fontWeight = FontWeight.Medium,
                color = colors.text,
                modifier = Modifier.weight(1f),
            )
            SanvyaIcon(
                SanvyaIcons.chevronRight,
                size = 18.dp,
                tint = colors.text2,
                modifier = Modifier.rotate(rotation),
            )
        }
        if (isOpen) {
            Text(
                item.answer,
                fontSize = 14.sp,
                color = colors.text2,
                lineHeight = 21.sp,
                modifier = Modifier.padding(start = 14.dp, end = 14.dp, bottom = 13.dp),
            )
        }
        Spacer(Modifier.size(0.dp))
    }
}
