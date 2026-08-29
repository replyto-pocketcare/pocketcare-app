package com.sanvya.app.ui.goals

import android.provider.Settings
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

/**
 * The "goal achieved" moment -- web's apps/web/src/goals/GoalCelebration.tsx.
 *
 * Web builds a real CSS 3D box with `transform-style: preserve-3d`: the goal
 * tile IS the cake's top face, six faces rotate together, and candles stand out
 * of the top face in the same 3D space. Compose has no `preserve-3d`. A
 * `graphicsLayer` applies a genuine perspective transform to ONE element, and
 * nested layers are flattened, so six faces cannot share a scene.
 *
 * So the scene is decomposed instead of faked, and it is decomposed around the
 * SAME angle web animates. `boxRotX` is web's `rotateX` on the box, and every
 * other quantity is derived from it:
 *
 * - the TILE is one `graphicsLayer` at `-(boxRotX + 90)`, so it is face-on at
 *   -90 (web's start: you are looking down at the tile) and foreshortened to
 *   `|sin(boxRotX)|` at -22 (web's settled pose);
 * - the cake BODY is drawn at `|cos(boxRotX)|` of its height, so it is invisible
 *   at -90 and nearly full at -22 -- the body grows out from under the tile
 *   exactly as the box turns;
 * - the CANDLES stand at the tile's far edge, which is `TileHeight *
 *   |sin(boxRotX)|` above the cake, so they follow the same turn.
 *
 * Everything else is web's, unchanged: the 2.5s rise/turn on
 * `cubic-bezier(0.22,0.9,0.24,1)`, the two confetti bursts at 520ms and 950ms
 * with 170 and 110 particles, gravity and fade over 7s, drag-to-orbit handed
 * over at 2.6s (which also cancels the auto-close), the 9s / 4.2s auto-dismiss,
 * and the flat reduced-motion card.
 */
@Composable
fun GoalCelebration(name: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    // Android's answer to `prefers-reduced-motion`. A user who has turned
    // animations off system-wide is told, not shown.
    val reduced = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val label = S.Goals.celebrationAria(sRes(), name)

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                // rgba(20,18,16,0.6) -- web's scrim exactly.
                .background(Color(0x99_14_12_10))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onDismiss,
                )
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            if (reduced) ReducedCelebration(name, onDismiss) else FullCelebration(name, onDismiss)
        }
    }
}

/** Web's `if (reduced)` branch: the same words, no motion. */
@Composable
private fun ReducedCelebration(name: String, onDismiss: () -> Unit) {
    val colors = LocalSanvyaColors.current
    // Web's reduced branch closes at 4.2s where the full one runs to 9s: there
    // is no animation to sit through, only words to read.
    LaunchedEffect(Unit) {
        delay(4200)
        onDismiss()
    }
    Column(
        modifier = Modifier
            .padding(28.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(20.dp))
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("🎂", fontSize = 72.sp)
        Text(
            S.Goals.achieved(sRes()).uppercase(),
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.7.sp,
            color = colors.accent,
        )
        Text(
            S.Goals.celebrationName(sRes(), name),
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = colors.text,
            textAlign = TextAlign.Center,
        )
        Text(S.Goals.celebrationBody(sRes()), fontSize = 14.sp, color = colors.text2, textAlign = TextAlign.Center)
    }
}

private val StageWidth = 300.dp
private val TileHeight = 190.dp
private val CakeThickness = 88.dp
private val CandleHeight = 46.dp
/** Tall enough for the tile face-on at the start, which is its largest pose. */
private val StageHeight = TileHeight + CakeThickness
/**
 * Where the cake's base sits inside the stage.
 *
 * Not the very bottom: at rest the candles reach about 200dp above the base,
 * and pinning the base to the floor would leave all the slack above the flames
 * and none below the plate, so the settled scene reads as sliding off the
 * bottom of its own box.
 */
private const val BaseLine = 0.86f

@Composable
private fun FullCelebration(name: String, onDismiss: () -> Unit) {
    val progress = remember { Animatable(0f) }
    var interactive by remember { mutableStateOf(false) }
    var orbited by remember { mutableStateOf(false) }
    // Floats, not derived state: these are read only inside `graphicsLayer` and
    // draw lambdas, so a drag redraws the layer without recomposing the tree.
    var rotX by remember { mutableFloatStateOf(-22f) }
    var rotY by remember { mutableFloatStateOf(0f) }
    var elapsedMs by remember { mutableLongStateOf(0L) }

    LaunchedEffect(Unit) {
        progress.animateTo(1f, tween(durationMillis = 2500, easing = CubicBezierEasing(0.22f, 0.9f, 0.24f, 1f)))
    }
    // Control is handed over once the entrance has settled -- web's 2600ms.
    LaunchedEffect(Unit) {
        delay(2600)
        interactive = true
    }
    LaunchedEffect(orbited) {
        // Restarting with `orbited = true` is what cancels the auto-close:
        // the user who is playing with the cake has said they are not done.
        if (orbited) return@LaunchedEffect
        delay(9000)
        onDismiss()
    }
    // A frame clock rather than an Animatable: the confetti is 280 particles
    // integrated per frame, and reading the time inside the draw lambda keeps
    // every one of those frames out of composition.
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (true) {
            val now = withFrameNanos { it }
            val ms = (now - start) / 1_000_000
            elapsedMs = ms
            if (ms > ConfettiLifeMs) break
        }
    }

    val confetti = remember { buildConfetti() }
    val flicker = rememberInfiniteTransition(label = "flames")
    // NOT `by`: delegating would read the value in COMPOSITION and recompose
    // this whole subtree sixty times a second for a candle flame. Held as the
    // State and read inside the draw lambda, the flicker only invalidates the
    // canvas.
    val flame = flicker.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Reverse),
        label = "flame",
    )

    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) { drawConfetti(confetti, elapsedMs) }

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Box(
                modifier = Modifier
                    .width(StageWidth)
                    .height(StageHeight)
                    .graphicsLayer {
                        val p = progress.value
                        translationY = entranceRise(p) * density
                        rotationY = if (interactive) rotY else entranceSpin(p)
                        cameraDistance = 14f * density
                    }
                    .pointerInput(interactive) {
                        if (!interactive) return@pointerInput
                        detectDragGestures { change, drag ->
                            change.consume()
                            orbited = true
                            // Web's own drag constants: 0.4 degrees per pixel,
                            // pitch clamped to +/-85 so the scene never flips.
                            rotY += drag.x * 0.4f
                            rotX = (rotX - drag.y * 0.4f).coerceIn(-85f, 85f)
                        }
                    },
            ) {
                Canvas(Modifier.fillMaxSize()) {
                    val angle = if (interactive) rotX else entranceTilt(progress.value)
                    drawCakeAndCandles(angle, flame.value)
                }
                GoalTile(
                    name = name,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .offset {
                            // A lambda, so the tile follows the cake's growing
                            // top edge without recomposing the tree once per
                            // frame. Same BaseLine the Canvas draws against.
                            val angle = if (interactive) rotX else entranceTilt(progress.value)
                            val bodyFactor = abs(cos(angle * DegreesToRadians))
                            IntOffset(
                                0,
                                -(StageHeight.toPx() * (1f - BaseLine) + CakeThickness.toPx() * bodyFactor).toInt(),
                            )
                        }
                        .fillMaxWidth()
                        .height(TileHeight)
                        .graphicsLayer {
                            val angle = if (interactive) rotX else entranceTilt(progress.value)
                            // -(boxRotX + 90): face-on at web's -90 start,
                            // foreshortened to the lid at web's -22 finish.
                            rotationX = -(angle + 90f)
                            transformOrigin = TransformOrigin(0.5f, 1f)
                            cameraDistance = 14f * density
                        },
                )
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    S.Goals.achieved(sRes()).uppercase(),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.8.sp,
                    // #f0c419 -- web's caption gold, which is not a theme token
                    // on either side. See CONFETTI_COLORS.
                    color = Color(0xFF_F0_C4_19),
                )
                Text(
                    S.Goals.celebrationName(sRes(), name),
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                )
                Text(
                    if (interactive) S.Goals.celebrationHintDrag(sRes()) else S.Goals.celebrationHint(sRes()),
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.padding(top = 4.dp),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

/** The goal card that becomes the cake's lid. Web's "TOP FACE = the goal tile". */
@Composable
private fun GoalTile(name: String, modifier: Modifier = Modifier) {
    val colors = LocalSanvyaColors.current
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(18.dp))
            .background(colors.surface)
            .border(1.dp, colors.border, RoundedCornerShape(18.dp))
            .padding(22.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(name, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = colors.text)
            Text(
                S.Goals.celebrationTileTag(sRes()),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.0.sp,
                color = colors.accent,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(S.Goals.celebrationTileFunded(sRes()), fontSize = 13.sp, color = colors.text2)
                Text(S.Goals.celebrationTilePct(sRes()), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = colors.text)
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(10.dp)
                    .clip(RoundedCornerShape(999.dp))
                    .background(Brush.horizontalGradient(listOf(colors.sage, colors.accent))),
            )
        }
    }
}

// ---------------------------------------------------------------------------
// The entrance, from web's `pc-cake-rise` keyframes. Percentages are web's.
// ---------------------------------------------------------------------------

private const val RiseBreak = 0.22f

private fun lerp(from: Float, to: Float, t: Float): Float = from + (to - from) * t.coerceIn(0f, 1f)

/** translateY: 44dp below, overshooting to -18dp, settling at 0. */
private fun entranceRise(p: Float): Float =
    if (p < RiseBreak) lerp(44f, -18f, p / RiseBreak) else lerp(-18f, 0f, (p - RiseBreak) / (1f - RiseBreak))

/** rotateX: flat on its back until the rise finishes, then up to web's -22. */
private fun entranceTilt(p: Float): Float =
    if (p < RiseBreak) -90f else lerp(-90f, -22f, (p - RiseBreak) / (1f - RiseBreak))

/** rotateY: a full turn during the same segment. */
private fun entranceSpin(p: Float): Float =
    if (p < RiseBreak) 0f else lerp(0f, 360f, (p - RiseBreak) / (1f - RiseBreak))

// ---------------------------------------------------------------------------
// The cake
// ---------------------------------------------------------------------------

/** Web's frosting band: white icing, a pink drip line at 26-34%, sponge below. */
private val Icing = Color(0xFF_FF_F4_F7)
private val Drip = Color(0xFF_F3_C9_D6)
private val Sponge = Color(0xFF_CF_90_79)
private val Plate = Color(0xFF_E9_E4_DC)
private val CandlePink = Color(0xFF_F4_C9_DB)
private val CandleBlue = Color(0xFF_CF_E0_F5)
private val FlameCore = Color(0xFF_FF_F2_A8)
private val FlameEdge = Color(0xFF_FF_6A_2E)

private val DegreesToRadians: Float = (Math.PI / 180.0).toFloat()

/**
 * Web places six candles, but at only THREE distinct x positions (34px in from
 * each edge and the centre, in a front and a back row). Seen from the front
 * those rows sit behind one another, so three columns is the same picture, not
 * a reduction.
 */
private val CandleSpots = listOf(0.113f, 0.5f, 0.887f)

private fun DrawScope.drawCakeAndCandles(boxRotX: Float, flame: Float) {
    val radians = boxRotX * DegreesToRadians
    // |cos| of the pitch: the front of the cake is edge-on at -90 and almost
    // square-on at -22, which is what makes the body appear as the tile turns.
    val bodyFactor = abs(cos(radians))
    // |sin| of the same angle is how much of the tile you still see, and the
    // candles stand at its far edge.
    val tileFactor = abs(sin(radians))
    if (bodyFactor < 0.02f) return

    val cakeHeight = CakeThickness.toPx() * bodyFactor
    val bottom = size.height * BaseLine
    val top = bottom - cakeHeight
    val corner = 12.dp.toPx()

    // Plate, a shallow ellipse the cake sits on.
    drawOval(
        color = Plate,
        topLeft = Offset(-8.dp.toPx(), bottom - 7.dp.toPx()),
        size = Size(size.width + 16.dp.toPx(), 14.dp.toPx()),
    )
    // Web's side faces are `borderRadius: "0 0 12px 12px"` -- round at the
    // BASE only. So the bands are painted bottom-up: the sponge carries the
    // rounding and is stretched upward by one corner radius, and each band
    // above it paints over that overhang.
    drawBand(top + cakeHeight * 0.34f, cakeHeight * 0.66f, Sponge, corner, roundBase = true)
    drawBand(top + cakeHeight * 0.26f, cakeHeight * 0.08f, Drip, corner, roundBase = false)
    drawBand(top, cakeHeight * 0.26f, Icing, corner, roundBase = false)

    // Candles rise from the tile's far edge, so they travel with the turn.
    val candleBase = top - TileHeight.toPx() * tileFactor
    val candleH = CandleHeight.toPx() * bodyFactor
    val candleW = 8.dp.toPx()
    CandleSpots.forEachIndexed { i, fraction ->
        val x = size.width * fraction - candleW / 2f
        drawRoundRect(
            color = if (i % 2 == 0) CandlePink else CandleBlue,
            topLeft = Offset(x, candleBase - candleH),
            size = Size(candleW, candleH),
            cornerRadius = CornerRadius(4.dp.toPx()),
        )
        // The flame: a squashed radial blob that breathes on web's 0.9s cycle,
        // offset per candle so the six are never in step.
        val phase = (flame + i * 0.17f) % 1f
        val scaleY = 1f + 0.12f * sin(phase * 2f * Math.PI.toFloat())
        val flameH = 18.dp.toPx() * scaleY
        drawOval(
            brush = Brush.radialGradient(listOf(FlameCore, FlameEdge)),
            topLeft = Offset(x + candleW / 2f - 6.dp.toPx(), candleBase - candleH - flameH),
            size = Size(12.dp.toPx(), flameH),
        )
    }
}

/** One horizontal band of the cake. Only the base band is rounded. */
private fun DrawScope.drawBand(top: Float, height: Float, color: Color, corner: Float, roundBase: Boolean) {
    if (height <= 0f) return
    if (roundBase) {
        drawRoundRect(
            color = color,
            topLeft = Offset(0f, top - corner),
            size = Size(size.width, height + corner),
            cornerRadius = CornerRadius(corner),
        )
    } else {
        drawRect(color = color, topLeft = Offset(0f, top), size = Size(size.width, height))
    }
}

// ---------------------------------------------------------------------------
// Confetti
// ---------------------------------------------------------------------------

/**
 * Web's `CONFETTI_COLORS`, copied rather than mapped onto the chart palette.
 *
 * These are not design tokens -- no CSS variable backs any of them, and the
 * generated `CHART_COLORS` is the earthy INSIGHT_PALETTE, which would make the
 * one celebratory moment in the app read like a bar chart.
 */
private val ConfettiColors = listOf(
    Color(0xFF_E8_A3_3D), Color(0xFF_9C_AE_8E), Color(0xFF_C9_8A_72), Color(0xFF_6D_5A_CF),
    Color(0xFF_D2_3A_5E), Color(0xFF_3F_7A_6A), Color(0xFF_F0_C4_19),
)

private const val ConfettiLifeMs = 7000L

/**
 * One particle, in web's units: velocities are per FRAME at 60fps, which is
 * what web's per-frame integration means, and the draw below converts elapsed
 * milliseconds into frames rather than re-deriving the physics.
 */
private data class Confetto(
    val offsetX: Float,
    val offsetY: Float,
    val vx: Float,
    val vy: Float,
    val rotation: Float,
    val spin: Float,
    val size: Float,
    val color: Color,
    val square: Boolean,
    val birthMs: Long,
)

/** Web's two bursts: 170 particles at 520ms, another 110 at 950ms. */
private fun buildConfetti(): List<Confetto> {
    val random = Random(0)
    fun burst(count: Int, birthMs: Long) = List(count) {
        val angle = random.nextFloat() * 2f * Math.PI.toFloat()
        val speed = 2f + random.nextFloat() * 9f
        Confetto(
            offsetX = (random.nextFloat() - 0.5f) * 60f,
            offsetY = (random.nextFloat() - 0.5f) * 40f,
            vx = cos(angle) * speed,
            vy = sin(angle) * speed - 4f,
            rotation = random.nextFloat() * 180f,
            spin = (random.nextFloat() - 0.5f) * 17f,
            size = 5f + random.nextFloat() * 7f,
            color = ConfettiColors[random.nextInt(ConfettiColors.size)],
            square = random.nextInt(2) == 0,
            birthMs = birthMs,
        )
    }
    return burst(170, 520L) + burst(110, 950L)
}

private fun DrawScope.drawConfetti(particles: List<Confetto>, elapsedMs: Long) {
    if (elapsedMs >= ConfettiLifeMs) return
    val alpha = (1f - elapsedMs.toFloat() / ConfettiLifeMs).coerceIn(0f, 1f)
    val centerX = size.width / 2f
    val centerY = size.height / 2f
    val scale = density

    for (p in particles) {
        val ageMs = elapsedMs - p.birthMs
        if (ageMs < 0) continue
        // Frames, at web's 60fps integration step.
        val t = ageMs / 16.667f
        // x = x0 + vx*t, y = y0 + vy*t + 0.06*t^2 -- the closed form of web's
        // `p.vy += 0.12` per frame. Its 0.99 horizontal drag is dropped: over
        // seven seconds it moves a particle a few pixels, and a closed form
        // keeps this identical to iOS frame-for-frame.
        val x = centerX + (p.offsetX + p.vx * t) * scale
        val y = centerY + (p.offsetY + p.vy * t + 0.06f * t * t) * scale
        if (y > size.height + 40f) continue
        val side = p.size * scale
        rotate(degrees = p.rotation + p.spin * t, pivot = Offset(x, y)) {
            if (p.square) {
                drawRect(
                    color = p.color.copy(alpha = alpha),
                    topLeft = Offset(x - side / 2f, y - side / 4f),
                    size = Size(side, side / 2f),
                )
            } else {
                drawCircle(color = p.color.copy(alpha = alpha), radius = side / 2f, center = Offset(x, y))
            }
        }
    }
}
