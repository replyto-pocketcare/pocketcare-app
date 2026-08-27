package com.sanvya.app.ui.join

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.ui.components.SanvyaText

/**
 * Accept a split-group invite — ported from `apps/web/app/join/page.tsx`.
 *
 * A centred card, not a [SanvyaPage]: web gives this route no heading row and
 * no chrome, because it is a landing for a link from outside the app rather
 * than a place inside it. Every visit ends by leaving — into the group, or into
 * sign-in.
 *
 * Mirrors iOS's JoinView.swift.
 */
@Composable
fun JoinScreen(
    token: String?,
    onJoined: (String) -> Unit,
    onSignIn: () -> Unit,
    viewModel: JoinViewModel = viewModel(),
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current

    // Hoisted: start() runs a coroutine and cannot call sRes(), which is
    // @Composable. Same rule the rest of this codebase follows.
    val opening = S.Join.opening(res)
    val missingToken = S.Join.missingToken(res)
    val needAuth = S.Join.needAuth(res)

    LaunchedEffect(token) { viewModel.start(token, opening, missingToken, needAuth) }

    val message by viewModel.message.collectAsState()
    val needsAuth by viewModel.needsAuth.collectAsState()
    val joinedGroupId by viewModel.joinedGroupId.collectAsState()

    LaunchedEffect(joinedGroupId) { joinedGroupId?.let(onJoined) }

    Box(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        contentAlignment = Alignment.Center,
    ) {
        SanvyaCard(padding = PaddingValues(32.dp), modifier = Modifier.widthIn(max = 420.dp)) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SanvyaIcon(SanvyaIcons.groups, size = 28.dp, tint = colors.accent)
                SanvyaText(S.Join.title(res), SanvyaType.h1.copy(textAlign = TextAlign.Center))
                message?.let {
                    SanvyaText(
                        it,
                        // `textAlign` on the STYLE, not the component: SanvyaText
                        // deliberately exposes no alignment parameter, and adding
                        // one for a single screen would widen the design system
                        // for a landing page.
                        SanvyaType.body.copy(textAlign = TextAlign.Center),
                        color = colors.text2,
                    )
                }
                if (needsAuth) {
                    SanvyaButton(onClick = onSignIn) {
                        SanvyaText(S.Join.signInCreate(res), SanvyaType.button)
                    }
                }
            }
        }
    }
}
