package com.sanvya.app.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType

/**
 * Text at a design-system style.
 *
 * Every screen goes through these rather than `Text(fontSize = 18.sp)`, for the
 * same reason web has `h2` and `.eyebrow` instead of inline styles: when the
 * scale moves, it moves in one place — the CSS — and regenerates.
 */
@Composable
fun SanvyaText(
    text: String,
    style: TextStyle,
    modifier: Modifier = Modifier,
    color: Color = LocalSanvyaColors.current.text,
    maxLines: Int = Int.MAX_VALUE,
    overflow: TextOverflow = TextOverflow.Clip,
) = Text(
    text = text,
    modifier = modifier,
    style = style,
    color = color,
    maxLines = maxLines,
    overflow = overflow,
)

@Composable
fun H1(text: String, modifier: Modifier = Modifier, compact: Boolean = true) =
    SanvyaText(text, if (compact) SanvyaType.h1Compact else SanvyaType.h1, modifier)

@Composable
fun H2(text: String, modifier: Modifier = Modifier) = SanvyaText(text, SanvyaType.h2, modifier)

/**
 * `.eyebrow` — the uppercase, tracked section label.
 *
 * Uppercasing happens here, not in the string catalog: web does it with
 * `text-transform`, so the underlying translation stays sentence case and a
 * locale where uppercasing is wrong (or lossy) can opt out in one place.
 */
@Composable
fun Eyebrow(text: String, modifier: Modifier = Modifier) = SanvyaText(
    text = text.uppercase(),
    style = SanvyaType.eyebrow,
    modifier = modifier,
    color = LocalSanvyaColors.current.text3,
)

/** `.muted` — secondary body copy. */
@Composable
fun Muted(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = SanvyaType.body,
) = SanvyaText(text, style, modifier, color = LocalSanvyaColors.current.text2)
