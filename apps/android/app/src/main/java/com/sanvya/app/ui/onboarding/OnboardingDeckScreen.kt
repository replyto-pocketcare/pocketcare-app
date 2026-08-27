package com.sanvya.app.ui.onboarding

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.auth.AuthViewModel
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaText

/**
 * The pre-auth slide deck — ported from `apps/web/app/onboarding/page.tsx`.
 *
 * Web's auth gate replaces to `/onboarding` when there is no session, and this
 * deck is what a first-time visitor meets before the login form. **Neither
 * native app had it**: both gated straight to the login screen, so the seven
 * slides explaining what Sanvya is were reachable on the web client only.
 *
 * Seven cards, each a glyph on a gradient plus a title and a paragraph, swiped
 * or stepped through; the last card offers the three ways in. [Prefs
 * .setOnboardingSeen] is written on the way out — from any of them — so it is a
 * first-run screen and not a wall.
 *
 * **`InstallGuide` is deliberately absent.** Web's deck ends with an "Install
 * the app" chip that opens PWA instructions. On a phone the app IS installed.
 * Recorded in docs/mobile/ABSENT-BY-DECISION.md.
 */
@Composable
fun OnboardingDeckScreen(
    onDone: () -> Unit,
    viewModel: AuthViewModel = viewModel(),
) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val busy by viewModel.busy.collectAsState()
    val error by viewModel.error.collectAsState()

    // Read outside the draw scope: a DrawScope is not a composable scope, so
    // the theme's CompositionLocal cannot be touched inside `drawBehind`.
    val bloomStart = colors.accentGhost
    val bloomEnd = colors.bg

    val slides = OnboardingSlides.slides
    val titles = OnboardingSlides.titles(res)
    val bodies = OnboardingSlides.bodies(res)
    // Survives rotation and process death: a deck that restarts at slide one
    // because the phone turned is a small thing that reads as a broken app.
    var index by rememberSaveable { mutableIntStateOf(0) }
    val isLast = index == slides.lastIndex

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.bg)
            // `radial-gradient(120% 90% at 50% 0%, accent-ghost, bg 60%)` — the
            // accent bloom behind the deck, from the top edge. Drawn rather
            // than passed to `background(brush)` because the centre and radius
            // are fractions of the drawn size, which only the draw scope knows.
            .drawBehind {
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(bloomStart, bloomEnd),
                        center = Offset(size.width / 2f, 0f),
                        radius = size.height * BLOOM_RADIUS_FRACTION,
                    )
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .widthIn(max = 520.dp)
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SanvyaText(
                S.Translation.appName(res),
                SanvyaType.h1.copy(textAlign = TextAlign.Center),
                color = colors.accent,
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .pointerInput(slides.size) {
                        var dragged = 0f
                        detectHorizontalDragGestures(
                            onDragStart = { dragged = 0f },
                            // Web's own thresholds: 60px either way, and it does
                            // not wrap around at either end.
                            onDragEnd = {
                                if (dragged < -SWIPE_THRESHOLD && index < slides.lastIndex) index++
                                else if (dragged > SWIPE_THRESHOLD && index > 0) index--
                            },
                        ) { _, amount -> dragged += amount }
                    },
                verticalArrangement = Arrangement.spacedBy(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Graphic(slides[index])
                SanvyaText(
                    titles[index],
                    SanvyaType.h1.copy(fontSize = 27.sp, textAlign = TextAlign.Center),
                )
                SanvyaText(
                    bodies[index],
                    SanvyaType.body.copy(fontSize = 16.sp, lineHeight = 25.6.sp, textAlign = TextAlign.Center),
                    color = colors.text2,
                    modifier = Modifier.widthIn(max = 440.dp),
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                slides.indices.forEach { k ->
                    val active = k == index
                    val width by animateDpAsState(if (active) 22.dp else 8.dp, tween(200), label = "dotWidth")
                    val tint by animateColorAsState(
                        if (active) colors.accent else colors.border,
                        tween(200),
                        label = "dotColor",
                    )
                    Box(
                        Modifier
                            .size(width = width, height = 8.dp)
                            .clip(RoundedCornerShape(999.dp))
                            .background(tint),
                    )
                }
            }

            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (!isLast) {
                    DeckButton(S.Onboarding.next(res), onClick = { index++ })
                    DeckButton(S.Onboarding.skip(res), ghost = true, onClick = { index = slides.lastIndex })
                } else {
                    // Both of web's first two buttons land on the same screen
                    // here. Web splits them with `?mode=signin`; this app's
                    // login screen has its own mode toggle and no entry
                    // parameter -- a pre-existing divergence, recorded in
                    // PARITY_AUDIT rather than papered over with two buttons
                    // that do the same thing invisibly.
                    DeckButton(S.Onboarding.createAccount(res), enabled = !busy, onClick = onDone)
                    DeckButton(S.Onboarding.signIn(res), ghost = true, enabled = !busy, onClick = onDone)
                    DeckButton(
                        if (busy) S.Onboarding.starting(res) else S.Onboarding.tryGuest(res),
                        ghost = true,
                        enabled = !busy,
                    ) {
                        // Only on success: a failed anonymous sign-in leaves the
                        // deck up with its error, exactly as web does, rather
                        // than dropping the user on a login screen with no
                        // explanation of what just went wrong.
                        viewModel.ensureGuest(onComplete = onDone)
                    }
                }
            }

            // Bound to a local first: `error` is a `by`-delegated property and
            // does not smart-cast across the null check.
            val message = error
            if (message != null) {
                SanvyaCard(padding = PaddingValues(12.dp)) {
                    SanvyaText(message, SanvyaType.body.copy(fontSize = 13.sp), color = colors.negative)
                }
            }

            SanvyaText(
                S.Onboarding.footer(res),
                SanvyaType.body.copy(fontSize = 12.sp, textAlign = TextAlign.Center),
                color = colors.text2,
            )
        }
    }
}

@Composable
private fun Graphic(slide: OnboardingSlide) {
    Box(
        modifier = Modifier
            .widthIn(max = 300.dp)
            .fillMaxWidth()
            .aspectRatio(16f / 10f)
            .clip(RoundedCornerShape(24.dp))
            .background(
                // 150deg in CSS, measured clockwise from "up" -- roughly
                // top-trailing to bottom-leading.
                Brush.linearGradient(
                    colors = listOf(slide.gradientStart, slide.gradientEnd),
                    start = Offset(Float.POSITIVE_INFINITY, 0f),
                    end = Offset(0f, Float.POSITIVE_INFINITY),
                )
            ),
        contentAlignment = Alignment.Center,
    ) {
        SanvyaText(
            slide.glyph,
            SanvyaType.h1.copy(fontSize = 68.sp, lineHeight = 68.sp),
            color = GLYPH_COLOR,
        )
    }
}

@Composable
private fun DeckButton(
    label: String,
    ghost: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val colors = LocalSanvyaColors.current
    SanvyaButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        enabled = enabled,
        ghost = ghost,
    ) {
        SanvyaText(
            label,
            SanvyaType.button.copy(textAlign = TextAlign.Center),
            color = if (ghost) colors.text else Color.White,
            modifier = Modifier.weight(1f),
        )
    }
}

/** `#f6f0e7` — web's glyph colour, a warm off-white that is not `--text`. */
private val GLYPH_COLOR = Color(0xFFF6F0E7)

/** Web's drag threshold, in pixels either way. */
private const val SWIPE_THRESHOLD = 60f

/** Web's `90%` vertical extent for the bloom. */
private const val BLOOM_RADIUS_FRACTION = 0.9f
