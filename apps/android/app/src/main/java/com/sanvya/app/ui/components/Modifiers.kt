package com.sanvya.app.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.Interaction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.toArgb
import com.sanvya.app.theme.LocalSanvyaShadows
import com.sanvya.app.theme.SanvyaMotion
import com.sanvya.app.theme.SanvyaShadow

/**
 * CSS `box-shadow`, layer for layer.
 *
 * Compose's own `Modifier.shadow()` is an *elevation* model — one blur, one
 * system-chosen colour, no offset control — and the design system's shadows are
 * two-layer with large negative spreads (`0 12px 30px -20px`), which elevation
 * cannot express at all. Painting through the framework paint's shadow layer
 * gives the same primitive the browser uses: colour, blur, dx, dy.
 *
 * Spread has no direct equivalent, so it is applied the way CSS defines it —
 * by growing (or, as here, shrinking) the shadow's shape before blurring.
 */
fun Modifier.sanvyaShadow(shadow: SanvyaShadow, shape: Shape): Modifier = drawBehind {
    shadow.layers.forEach { layer ->
        val spread = layer.spread.toPx()
        val w = size.width + spread * 2
        val h = size.height + spread * 2
        if (w <= 0f || h <= 0f) return@forEach

        val outline: Outline = shape.createOutline(Size(w, h), layoutDirection, this)
        val paint = Paint()
        paint.asFrameworkPaint().apply {
            // The shape itself must not paint — only its shadow.
            color = android.graphics.Color.TRANSPARENT
            setShadowLayer(
                // A zero radius disables the shadow layer entirely rather than
                // drawing a hard edge, so hairline shadows get a minimum.
                layer.blur.toPx().coerceAtLeast(0.01f),
                layer.x.toPx(),
                layer.y.toPx(),
                layer.color.toArgb(),
            )
        }
        drawIntoCanvas { canvas ->
            canvas.save()
            canvas.translate(-spread, -spread)
            canvas.drawOutline(outline, paint)
            canvas.restore()
        }
    }
}

@Composable
fun Modifier.sanvyaShadow(shadow: (com.sanvya.app.theme.SanvyaShadows) -> SanvyaShadow, shape: Shape): Modifier =
    sanvyaShadow(shadow(LocalSanvyaShadows.current), shape)

/**
 * `.press` — the design system's universal tap feedback: scale to 0.97 over
 * 120ms. Web applies it to every interactive element, so this is attached
 * wherever a `.press` class appears rather than relying on Material's ripple,
 * which is a different feedback language.
 */
@Composable
fun Modifier.press(interactionSource: MutableInteractionSource): Modifier {
    val pressed = interactionSource.collectIsPressedAsStateCompat()
    val scale by animateFloatAsState(
        targetValue = if (pressed) SanvyaMotion.pressScale else 1f,
        animationSpec = tween(SanvyaMotion.pressDurationMs, easing = SanvyaMotion.standard),
        label = "press",
    )
    return this.scale(scale)
}

/**
 * `.lift:active` — the gentler 0.985 used by cards and tiles, which web
 * distinguishes from `.press` because a whole card snapping 3% feels wrong at
 * card size.
 */
@Composable
fun Modifier.liftPress(interactionSource: MutableInteractionSource): Modifier {
    val pressed = interactionSource.collectIsPressedAsStateCompat()
    val scale by animateFloatAsState(
        targetValue = if (pressed) SanvyaMotion.liftPressScale else 1f,
        animationSpec = tween(SanvyaMotion.liftPressDurationMs, easing = SanvyaMotion.standard),
        label = "liftPress",
    )
    return this.scale(scale)
}

/**
 * Local re-implementation of `collectIsPressedAsState`.
 *
 * The stock helper lives in `androidx.compose.foundation.interaction` and is
 * fine, but it discards the interaction stack on recomposition in a way that
 * loses a press that began before the composable was attached — visible as a
 * tile that never un-scales after a fast tap. Tracking the stack explicitly
 * fixes that and costs a dozen lines.
 */
@Composable
private fun MutableInteractionSource.collectIsPressedAsStateCompat(): Boolean {
    val stack = remember(this) { mutableListOf<PressInteraction.Press>() }
    var pressed by remember(this) { mutableStateOf(false) }
    androidx.compose.runtime.LaunchedEffect(this) {
        interactions.collect { interaction: Interaction ->
            when (interaction) {
                is PressInteraction.Press -> stack.add(interaction)
                is PressInteraction.Release -> stack.remove(interaction.press)
                is PressInteraction.Cancel -> stack.remove(interaction.press)
            }
            pressed = stack.isNotEmpty()
        }
    }
    return pressed
}
