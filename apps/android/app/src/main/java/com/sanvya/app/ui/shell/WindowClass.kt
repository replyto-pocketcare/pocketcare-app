package com.sanvya.app.ui.shell

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import com.sanvya.app.theme.SanvyaMetrics

/**
 * What kind of device this is, decided the way the platform decides it.
 *
 * Not by screen size: a folded foldable is phone-sized and a foldable in
 * split-screen is smaller still, but it is a foldable either way, and the
 * orientation policy below turns on the hardware rather than on how much room
 * the app happens to have right now.
 */
enum class SanvyaDeviceType {
    /** A phone with no hinge. */
    PHONE,

    /** Has a hinge, whatever posture it is in at the moment. */
    FOLDABLE,

    /** No hinge, `sw >= 600dp`. */
    TABLET;

    /**
     * Orientation policy (Akhilesh, 2026-08-23): phones stay portrait; anything
     * that can reasonably be held or propped sideways rotates freely.
     *
     * Worth knowing: from Android 16 the system **ignores** an orientation
     * restriction on displays at or above `sw600dp` anyway. So this is not
     * fighting the platform — on the devices where the lock still binds
     * (phones) it is what we want, and on the devices where it would be
     * overridden (tablets, unfolded foldables) we are not asking for it.
     */
    val lockedToPortrait: Boolean get() = this == PHONE
}

/**
 * Reads the device type from the platform's own capability flags.
 *
 * - `FEATURE_SENSOR_HINGE_ANGLE` is the hinge-angle sensor every Android
 *   foldable reports. It is a property of the *device*, so it stays true when
 *   the device is folded shut and running on the cover display — which a
 *   posture or window-size check would not.
 * - `smallestScreenWidthDp` is the value behind the `sw600dp` resource
 *   qualifier: the width of the smaller dimension, and therefore the same
 *   number in both orientations.
 *
 * Hinge is tested first so a large foldable is FOLDABLE rather than TABLET.
 * Both rotate freely, so nothing depends on that today — but the two will
 * diverge as soon as anything cares about the fold itself.
 */
fun Context.sanvyaDeviceType(): SanvyaDeviceType = when {
    packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE) ->
        SanvyaDeviceType.FOLDABLE
    resources.configuration.smallestScreenWidthDp >= TABLET_SW_DP ->
        SanvyaDeviceType.TABLET
    else -> SanvyaDeviceType.PHONE
}

/** The `sw600dp` qualifier, as a number. */
private const val TABLET_SW_DP = 600

/**
 * Which shell layout the current window is big enough for.
 *
 * Derived from Material 3's own breakpoints (`SanvyaMetrics.WindowClass`), not
 * from web's CSS pixel widths. The two disagree — web switches at 640/860/1024, Material
 * at 600/840 — and the platform's numbers win here, because they are the ones
 * every other Android app on the device already switches at, and because they
 * are measured against how Android devices actually cluster rather than how a
 * browser window resizes.
 */
enum class SanvyaWindowClass {
    /** Width < 600dp. Bottom bar, icons only. Every phone in portrait. */
    COMPACT,

    /** 600dp <= width < 840dp. Bottom bar with labels; content capped. */
    MEDIUM,

    /** Width >= 840dp with room to stand it up. Sidebar, top bar, window frame. */
    EXPANDED;

    /** Whether the floating bottom bar is the navigation at this size. */
    val usesBottomBar: Boolean get() = this != EXPANDED

    /** Web hides the bar's text labels on its smallest tier; so do we. */
    val showsNavLabels: Boolean get() = this != COMPACT

    /** Whether the content column is capped and centred rather than full-bleed. */
    val capsContentWidth: Boolean get() = this != COMPACT
}

/**
 * The current window class.
 *
 * `EXPANDED` deliberately requires height as well as width. A short, wide
 * window — a folded foldable turned sideways, a squat freeform window — has the
 * width for a sidebar and nowhere to put it; the sidebar is a full-height
 * column and would leave the content a letterbox. Material's own guidance is
 * to check both, and this is the case where it matters.
 */
fun windowClassOf(widthDp: Int, heightDp: Int): SanvyaWindowClass = when {
    widthDp >= SanvyaMetrics.WindowClass.expandedWidth &&
        heightDp >= SanvyaMetrics.WindowClass.mediumHeight -> SanvyaWindowClass.EXPANDED
    widthDp >= SanvyaMetrics.WindowClass.mediumWidth -> SanvyaWindowClass.MEDIUM
    else -> SanvyaWindowClass.COMPACT
}

val LocalWindowClass = compositionLocalOf { SanvyaWindowClass.COMPACT }
val LocalDeviceType = compositionLocalOf { SanvyaDeviceType.PHONE }

/**
 * Publishes [LocalWindowClass] and [LocalDeviceType], and applies the
 * orientation policy.
 *
 * Wrap the app once, at the root.
 *
 * A window-class change is a **resize, not a relaunch**: nothing below may
 * treat crossing a breakpoint, unfolding, or being dragged wider in
 * split-screen as a fresh start. Scroll position, the selected tab, an open
 * sheet and in-progress form input all survive it.
 */
@Composable
fun ProvideWindowClass(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val deviceType = remember(context) { context.sanvyaDeviceType() }

    // `Configuration.screenWidthDp` is the **app window's** width, not the
    // display's: in split-screen, freeform and on a folded cover display it
    // reports what the app actually got. That is the number the breakpoints
    // are meant to be compared against.
    val config = LocalConfiguration.current
    val windowClass = remember(config.screenWidthDp, config.screenHeightDp) {
        windowClassOf(config.screenWidthDp, config.screenHeightDp)
    }

    ApplyOrientationPolicy(deviceType)

    CompositionLocalProvider(
        LocalWindowClass provides windowClass,
        LocalDeviceType provides deviceType,
        content = content,
    )
}

/**
 * Sets `requestedOrientation` from the device type, and puts it back on the way
 * out.
 *
 * Restoring on dispose is not ceremony: `requestedOrientation` is Activity
 * state, not composable state, so leaving it set would outlive this shell and
 * pin any later screen — a full-screen receipt camera, say — to portrait too.
 */
@Composable
private fun ApplyOrientationPolicy(deviceType: SanvyaDeviceType) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }

    DisposableEffect(activity, deviceType) {
        val previous = activity?.requestedOrientation
        activity?.requestedOrientation = if (deviceType.lockedToPortrait) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
        onDispose {
            if (previous != null) activity?.requestedOrientation = previous
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
