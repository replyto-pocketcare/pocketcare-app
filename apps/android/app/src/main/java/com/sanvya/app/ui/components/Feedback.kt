package com.sanvya.app.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaMotion
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType

/**
 * The rotating ring spinner: an `--accent-ghost` track with an `--accent` arc,
 * one turn every 800ms, linear.
 *
 * Not `CircularProgressIndicator` — Material's indicator sweeps its arc length
 * as it spins, which is a visibly different animation from web's fixed arc.
 */
@Composable
fun Spinner(size: Dp = 28.dp, stroke: Dp = 3.dp) {
    val colors = LocalSanvyaColors.current
    val transition = rememberInfiniteTransition(label = "spinner")
    val angle by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(800, easing = LinearEasing)),
        label = "spinnerAngle",
    )
    Canvas(modifier = Modifier.size(size)) {
        val w = stroke.toPx()
        val inset = w / 2
        val arcSize = Size(this.size.width - w, this.size.height - w)
        drawArc(
            color = colors.accentGhost,
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = arcSize,
            style = Stroke(width = w),
        )
        // A quarter turn of accent — web colours only `border-top-color`.
        drawArc(
            color = colors.accent,
            startAngle = angle - 90f,
            sweepAngle = 90f,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = arcSize,
            style = Stroke(width = w),
        )
    }
}

/** Full-area centred loader with an optional label. */
@Composable
fun Loading(label: String? = null, modifier: Modifier = Modifier) = Column(
    modifier = modifier.fillMaxSize(),
    verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
) {
    Spinner(size = 34.dp)
    if (label != null) Muted(label, style = SanvyaType.chip)
}

/**
 * `.skeleton` — a recessed block pulsing between 0.5 and 1 opacity on a
 * 1.4s cycle. Web layers a sweeping gradient over it; the opacity pulse is the
 * same rhythm without a shader, and reads identically at list scale.
 */
@Composable
fun Skeleton(
    height: Dp = 16.dp,
    modifier: Modifier = Modifier,
    radius: Dp = 8.dp,
) {
    val colors = LocalSanvyaColors.current
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(
        initialValue = 0.5f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            tween(SanvyaMotion.shimmerDurationMs / 2),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "skeletonAlpha",
    )
    Box(
        modifier = modifier
            .height(height)
            .clip(RoundedCornerShape(radius))
            .alpha(alpha)
            .background(colors.surface2),
    )
}

/** Animated 0–100 bar. `color` signals threshold/over states, as on web. */
@Composable
fun ProgressBar(
    pct: Float,
    modifier: Modifier = Modifier,
    color: Color? = null,
    height: Dp = 10.dp,
) {
    val colors = LocalSanvyaColors.current
    val clampedPct = pct.coerceIn(0f, 100f)
    val animated by animateFloatAsState(
        targetValue = clampedPct / 100f,
        animationSpec = tween(400, easing = SanvyaMotion.standard),
        label = "progress",
    )
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(SanvyaShape.pill)
            .background(colors.surface2),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(animated)
                .height(height)
                .clip(SanvyaShape.pill)
                .background(color ?: colors.accent),
        )
    }
}
