package com.sanvya.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

/**
 * The design system's dialog: a `.card` floating on a 45%-opacity scrim, 440dp
 * wide at most, 24dp padding, entering with a spring from 0.94 scale.
 *
 * Uses `Dialog` rather than an in-tree overlay so the system owns it — that is
 * what gives back-button dismissal, correct IME insets and the accessibility
 * focus containment web has to hand-roll (its `Modal` implements a full focus
 * trap in JS; on Android the platform does it).
 *
 * `usePlatformDefaultWidth = false` because the platform default caps dialog
 * width well below 440dp on phones.
 */
@Composable
fun SanvyaModal(
    open: Boolean,
    onClose: () -> Unit,
    label: String? = null,
    dismissOnScrimTap: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    if (!open) return
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            dismissOnClickOutside = dismissOnScrimTap,
        ),
    ) {
        val scrimInteraction = remember { MutableInteractionSource() }
        Box(
            modifier = Modifier
                .fillMaxSize()
                // rgba(43,39,35,0.45) — the ink colour at 45%, not plain black.
                .background(Color(0x73_2B_27_23))
                .then(
                    if (dismissOnScrimTap) {
                        Modifier.clickable(
                            interactionSource = scrimInteraction,
                            indication = null,
                            onClick = onClose,
                        )
                    } else {
                        Modifier
                    },
                )
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            AnimatedVisibility(
                visible = true,
                enter = fadeIn(spring(stiffness = Spring.StiffnessMediumLow)) +
                    scaleIn(spring(dampingRatio = 0.75f, stiffness = 220f), initialScale = 0.94f),
                exit = fadeOut() + scaleOut(targetScale = 0.96f),
            ) {
                SanvyaCard(
                    // Swallow taps so a tap on the card does not reach the scrim.
                    modifier = Modifier
                        .widthIn(max = 440.dp)
                        .fillMaxWidth()
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = {},
                        )
                        .then(
                            if (label != null) {
                                Modifier.paneTitleSemantics(label)
                            } else {
                                Modifier
                            },
                        ),
                    padding = androidx.compose.foundation.layout.PaddingValues(24.dp),
                    content = content,
                )
            }
        }
    }
}

/** `paneTitle` is what TalkBack announces when a dialog takes focus. */
private fun Modifier.paneTitleSemantics(title: String): Modifier = semantics { paneTitle = title }

/**
 * The blocking, non-dismissable variant used while a destructive write is in
 * flight (web renders `GlobalLoader` over the page for the same purpose).
 */
@Composable
fun BlockingLoader(open: Boolean, label: String? = null) {
    if (!open) return
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
        ),
    ) {
        Box(
            modifier = Modifier.fillMaxSize().background(Color(0x73_2B_27_23)),
            contentAlignment = Alignment.Center,
        ) {
            Loading(label)
        }
    }
}
