package com.sanvya.app.speech

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

/**
 * Live dictation, behind an interface.
 *
 * The interface exists for the same reason `PdfTextExtractor`'s does: the thing
 * behind it can be absent at runtime and that must not be a crash. A device
 * with no recognition service installed (a plain AOSP build, a phone where the
 * user disabled Google's app) answers `isRecognitionAvailable` false, and the
 * mic button is then not drawn at all rather than drawn and dead -- which is
 * exactly what web does when `voiceSupported()` is false.
 *
 * Mirrors iOS's `SpeechDictating`.
 */
interface SpeechDictation {
    /** False means: do not draw the button. */
    fun isAvailable(): Boolean

    /**
     * Begin listening.
     *
     * [onPartial] fires repeatedly with the best guess so far; [onFinal] once
     * with the recogniser's answer; [onDone] exactly once, whatever happened,
     * so the caller can return to idle from one place. [onSpeechEnded] marks
     * the gap where the recogniser has stopped hearing and has not answered
     * yet -- web calls that state "transcribing".
     */
    fun start(
        onPartial: (String) -> Unit,
        onSpeechEnded: () -> Unit,
        onFinal: (String) -> Unit,
        onDone: (SpeechError?) -> Unit,
    )

    /** Stop listening and take whatever has been heard. Web's `rec.stop()`. */
    fun stop()

    /** Stop listening and discard. Web's `rec.abort()`. */
    fun cancel()

    /** Free the platform recogniser. Must be called from the main thread. */
    fun release()
}

/**
 * Why dictation ended badly.
 *
 * Only the two the UI reacts to differently are named. Everything else is
 * [OTHER]: web's `onError` handler does not branch either -- it returns the
 * button to idle and leaves the composer alone, on the reasoning that a failed
 * dictation the user can simply retry does not deserve an error message.
 */
enum class SpeechError { PERMISSION_DENIED, NO_MATCH, OTHER }

/** The no-op used when the platform has no recogniser. */
object NoSpeechDictation : SpeechDictation {
    override fun isAvailable() = false
    override fun start(
        onPartial: (String) -> Unit,
        onSpeechEnded: () -> Unit,
        onFinal: (String) -> Unit,
        onDone: (SpeechError?) -> Unit,
    ) = onDone(SpeechError.OTHER)
    override fun stop() {}
    override fun cancel() {}
    override fun release() {}
}

/**
 * `android.speech.SpeechRecognizer`.
 *
 * On-device is PREFERRED, not required. `createOnDeviceSpeechRecognizer` (API
 * 31+) never leaves the phone but only supports the languages the user has
 * downloaded, and silently returns nothing for the rest; the general recogniser
 * with `EXTRA_PREFER_OFFLINE` uses on-device when it can and the network when
 * it cannot. Web's own comment makes the same trade in the other direction --
 * it prefers Whisper "private default" and falls back to a browser service that
 * may be remote. Privacy that turns dictation off for most of the world is not
 * the choice this product makes; what it does instead is tell the user, in the
 * composer's own placeholder, that the mic is there.
 *
 * Every method must be called from the main thread -- the platform class says
 * so, and violating it fails silently rather than throwing.
 */
class PlatformSpeechDictation(private val context: Context) : SpeechDictation {
    private var recognizer: SpeechRecognizer? = null
    private var finished = false

    override fun isAvailable(): Boolean =
        runCatching { SpeechRecognizer.isRecognitionAvailable(context) }.getOrDefault(false)

    override fun start(
        onPartial: (String) -> Unit,
        onSpeechEnded: () -> Unit,
        onFinal: (String) -> Unit,
        onDone: (SpeechError?) -> Unit,
    ) {
        release()
        finished = false
        val instance = runCatching { SpeechRecognizer.createSpeechRecognizer(context) }.getOrNull()
        if (instance == null) {
            onDone(SpeechError.OTHER)
            return
        }
        recognizer = instance

        // `finished` guards a real double-callback: a recogniser that errors
        // AFTER delivering results calls both onResults and onError, and
        // letting the second one through would take the button out of a state
        // the first one had already left.
        fun finish(error: SpeechError?) {
            if (finished) return
            finished = true
            onDone(error)
        }

        instance.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() = onSpeechEnded()
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onPartialResults(partialResults: Bundle?) {
                bestOf(partialResults)?.let(onPartial)
            }

            override fun onResults(results: Bundle?) {
                bestOf(results)?.let(onFinal)
                finish(null)
            }

            override fun onError(error: Int) {
                finish(
                    when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> SpeechError.PERMISSION_DENIED
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                        -> SpeechError.NO_MATCH
                        else -> SpeechError.OTHER
                    },
                )
            }
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            // The DEVICE's language, matching web's `rec.lang = navigator.language`.
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
        }
        runCatching { instance.startListening(intent) }.onFailure { finish(SpeechError.OTHER) }
    }

    override fun stop() {
        runCatching { recognizer?.stopListening() }
    }

    override fun cancel() {
        runCatching { recognizer?.cancel() }
    }

    override fun release() {
        runCatching { recognizer?.destroy() }
        recognizer = null
    }

    /**
     * The recogniser's best guess.
     *
     * `RESULTS_RECOGNITION` is ordered by confidence, so the first entry is the
     * answer -- the rest are alternatives no part of this screen offers.
     */
    private fun bestOf(bundle: Bundle?): String? =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.takeIf { it.isNotEmpty() }
}
