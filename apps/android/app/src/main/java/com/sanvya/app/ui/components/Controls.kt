package com.sanvya.app.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.LocalSanvyaShadows
import com.sanvya.app.theme.SanvyaMotion
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType

/**
 * `.btn` — the terracotta pill.
 *
 * Deliberately not `androidx.compose.material3.Button`: Material's button
 * brings its own elevation model, ripple, minimum size and disabled colours,
 * all of which differ from the design system's, and overriding every one of
 * them is more code than drawing the button.
 */
@Composable
fun SanvyaButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    ghost: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    val shape = SanvyaShape.pill

    var m = modifier.press(interaction)
    // `.btn.ghost` is surface + a strong border and, notably, NO shadow.
    if (!ghost && enabled) m = m.sanvyaShadow(LocalSanvyaShadows.current.shadowAccent, shape)
    m = m
        .clip(shape)
        .background(if (ghost) colors.surface else colors.accent)
    if (ghost) m = m.border(1.dp, colors.borderStrong, shape)
    m = m
        .clickable(
            interactionSource = interaction,
            indication = null,
            enabled = enabled,
            onClick = onClick,
        )
        .defaultMinSize(minHeight = 40.dp)
        .padding(horizontal = 16.dp, vertical = 10.dp)
        // `.btn:disabled { opacity: 0.45 }` — the whole control fades, label
        // included, rather than swapping in a separate disabled palette.
        .alpha(if (enabled) 1f else 0.45f)

    androidx.compose.runtime.CompositionLocalProvider(
        LocalTextStyle provides SanvyaType.button.copy(
            color = if (ghost) colors.text else Color.White,
        ),
    ) {
        Row(
            modifier = m,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
            content = content,
        )
    }
}

/** `.chip` — pill, hairline border; `[data-active]` fills with the accent. */
@Composable
fun SanvyaChip(
    label: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    val shape = SanvyaShape.pill
    val bg by animateColorAsState(
        if (active) colors.accent else colors.surface,
        tween(SanvyaMotion.colorFadeDurationMs),
        label = "chipBg",
    )
    val fg by animateColorAsState(
        if (active) Color.White else colors.text,
        tween(SanvyaMotion.colorFadeDurationMs),
        label = "chipFg",
    )
    Box(
        modifier = modifier
            .press(interaction)
            .clip(shape)
            .background(bg)
            .border(1.dp, if (active) colors.accent else colors.border, shape)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            // Phones (<560px) tighten the horizontal padding to 8 so header
            // chip rows stay on one line.
            .padding(horizontal = 8.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        SanvyaText(label, SanvyaType.chip, color = fg, maxLines = 1)
    }
}

/**
 * `.input` — 12dp radius, hairline border, accent-soft focus ring.
 *
 * Built on `BasicTextField` rather than `OutlinedTextField` for the same reason
 * as the button: Material's text field imposes its own container height, label
 * animation and indicator line, none of which the design has.
 */
@Composable
fun SanvyaInput(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String? = null,
    enabled: Boolean = true,
    singleLine: Boolean = true,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = LocalSanvyaColors.current
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val shape = SanvyaShape.radiusSm

    val border by animateColorAsState(
        if (focused) colors.accentSoft else colors.border,
        tween(SanvyaMotion.colorFadeDurationMs),
        label = "inputBorder",
    )

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.surface)
            // The focus ring is `box-shadow: 0 0 0 3px var(--accent-ghost)` —
            // a solid 3px halo, not a blur, so it is a border and not a shadow.
            .border(if (focused) 3.dp else 0.dp, if (focused) colors.accentGhost else Color.Transparent, shape)
            .border(1.dp, border, shape)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        leading?.invoke()
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (value.isEmpty() && placeholder != null) {
                SanvyaText(placeholder, SanvyaType.body, color = colors.text2, maxLines = 1)
            }
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = singleLine,
                textStyle = SanvyaType.body.copy(color = colors.text),
                cursorBrush = SolidColor(colors.accent),
                interactionSource = interaction,
                keyboardOptions = keyboardOptions,
                visualTransformation = visualTransformation,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        trailing?.invoke()
    }
}
