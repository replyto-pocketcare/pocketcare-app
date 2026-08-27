package com.sanvya.app.ui.assistant

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.sanvya.app.domain.assistant.VoiceStatus
import com.sanvya.app.domain.assistant.mergeDictation
import com.sanvya.app.domain.assistant.voiceActive
import com.sanvya.app.domain.assistant.voiceTappable
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.speech.PlatformSpeechDictation
import com.sanvya.app.speech.SpeechError
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaShape
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.SanvyaMicIcon
import com.sanvya.app.ui.components.SanvyaText

/**
 * The composer's mic -- ported from `apps/web/src/assistant/MicButton.tsx`.
 *
 * Tap to start, tap to stop. Web's own summary of the behaviour, kept:
 * "Inserts text into the composer -- the assistant still replies in text."
 *
 * Three things it does NOT do, each on purpose:
 *
 *  * **It draws nothing when there is no recogniser.** Web returns `null` for
 *    `status === "unsupported"`; so does this. A mic that cannot listen is a
 *    dead control.
 *  * **It does not ask for the microphone until tapped.** Web cannot ask early
 *    either -- `getUserMedia` prompts on use -- and a permission dialog on the
 *    way into a chat screen is a worse first impression than one on the way
 *    into dictation.
 *  * **It says nothing when a dictation fails.** Web's `onError` returns the
 *    button to idle and leaves the composer alone. The one exception is a
 *    REFUSED permission, which is not a failure the user can retry their way
 *    out of -- that one gets a line, because the fix is in Settings and
 *    nothing on this screen would ever say so.
 *
 * Mirrors iOS's MicButtonView.swift.
 */
@Composable
fun MicButton(
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean,
    onDenied: (String) -> Unit,
) {
    val colors = LocalSanvyaColors.current
    val res = sRes()
    val context = LocalContext.current
    val dictation = remember { PlatformSpeechDictation(context) }

    // Asked once, at composition, because the answer decides whether the button
    // exists at all. It cannot change while this screen is open.
    val supported = remember { dictation.isAvailable() }

    var status by remember { mutableStateOf(if (supported) VoiceStatus.IDLE else VoiceStatus.UNSUPPORTED) }
    // The composer's contents at the moment the mic was tapped. Web captures
    // the same thing in `baseRef` and merges against it on every partial, so
    // the dictation replaces itself as it grows instead of appending to itself.
    var base by remember { mutableStateOf("") }

    DisposableEffect(Unit) { onDispose { dictation.release() } }

    fun begin() {
        base = value
        status = VoiceStatus.LISTENING
        dictation.start(
            onPartial = { onValueChange(mergeDictation(base, it)) },
            onSpeechEnded = { if (status == VoiceStatus.LISTENING) status = VoiceStatus.TRANSCRIBING },
            onFinal = { onValueChange(mergeDictation(base, it)) },
            onDone = { error ->
                status = VoiceStatus.IDLE
                if (error == SpeechError.PERMISSION_DENIED) onDenied(S.Assistant.micDenied(res))
            },
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) begin() else onDenied(S.Assistant.micDenied(res))
    }

    if (status == VoiceStatus.UNSUPPORTED) return

    val active = voiceActive(status)
    val tappable = enabled && voiceTappable(status)

    // Web's `micPulse` keyframes: a 1.4s ring that grows and fades. Compose has
    // no box-shadow, so the pulse is the button itself breathing -- the same
    // 1.4s, the same ease-in-out, and the same "only while active".
    val transition = rememberInfiniteTransition(label = "micPulse")
    val pulse by if (active) {
        transition.animateFloat(
            initialValue = 1f,
            targetValue = 1.08f,
            animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
            label = "micPulseScale",
        )
    } else {
        animateFloatAsState(1f, label = "micPulseScale")
    }

    Box(
        modifier = Modifier
            .size(40.dp)
            .scale(pulse)
            .clip(SanvyaShape.pill)
            .background(if (active) colors.accent else Color.Transparent)
            .clickable(enabled = tappable) {
                when (status) {
                    VoiceStatus.IDLE ->
                        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                            == PackageManager.PERMISSION_GRANTED
                        ) {
                            begin()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    // Set here as well as from `onSpeechEnded`: a tap that
                    // stops a recogniser which never heard anything gets no
                    // `onEndOfSpeech` at all, and the button would sit on
                    // LISTENING until the final callback arrived.
                    VoiceStatus.LISTENING -> {
                        status = VoiceStatus.TRANSCRIBING
                        dictation.stop()
                    }
                    else -> Unit
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        when (status) {
            // Web shows a percentage while Whisper downloads and runs. There is
            // no download here and no progress to report, so it shows the
            // ellipsis web falls back to when it has no number either.
            VoiceStatus.TRANSCRIBING -> SanvyaText(
                "…",
                SanvyaType.chip,
                color = colors.text2,
            )
            // Web's stop indicator: a 12px white square with a 3px radius.
            VoiceStatus.LISTENING -> Box(
                Modifier.size(12.dp).clip(RoundedCornerShape(3.dp)).background(Color.White),
            )
            else -> SanvyaMicIcon(
                size = 19.dp,
                tint = colors.text2,
                description = S.Assistant.micSpeak(res),
            )
        }
    }
}
