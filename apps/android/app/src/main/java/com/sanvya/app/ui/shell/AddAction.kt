package com.sanvya.app.ui.shell

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.staticCompositionLocalOf
import com.sanvya.app.theme.SanvyaIcons

/**
 * The bottom bar's "+" is contextual: each screen decides what it does.
 *
 * Mirrors `apps/web/src/ui/AddAction.tsx`. Three shapes, and the distinction
 * matters — a screen with one sensible add action fires immediately, and only a
 * screen with a genuine choice opens a menu. Web is careful about this and a
 * popover-for-everything version would feel slower on every screen.
 */
sealed interface AddAction {
    val label: String

    /** Navigate straight to a route. No menu. */
    data class Link(override val label: String, val route: String) : AddAction

    /** Run something immediately. No menu. */
    data class Button(override val label: String, val onClick: () -> Unit) : AddAction

    /** Offer a choice. Opens the add popover. */
    data class Menu(override val label: String, val items: List<Item>) : AddAction {
        data class Item(
            val key: String,
            val label: String,
            val glyph: String,
            val route: String? = null,
            val onClick: (() -> Unit)? = null,
            /** Shows a lock rather than a tier name — see the default below. */
            val locked: Boolean = false,
        )
    }
}

/** Set by the shell; screens register through [RegisterAddAction]. */
val LocalAddActionSetter = staticCompositionLocalOf<(AddAction?) -> Unit> { {} }

/**
 * Registers this screen's add action for as long as it is composed, and clears
 * it on the way out so the next screen does not inherit it.
 */
@Composable
fun RegisterAddAction(action: AddAction) {
    val setter = LocalAddActionSetter.current
    DisposableEffect(action) {
        setter(action)
        onDispose { setter(null) }
    }
}

/**
 * What the "+" does on a screen that has registered nothing.
 *
 * A transaction — or a scanned receipt, which becomes one — is the thing that
 * is always relevant in a money app. Receipt scanning shows a **lock**, not a
 * tier name: the plans are Lite and Pro, so naming one would be either wrong or
 * only half the answer.
 */
fun defaultAddAction(canScan: Boolean): AddAction = AddAction.Menu(
    label = "Add",
    items = listOf(
        AddAction.Menu.Item(
            key = "transaction",
            label = "Add transaction",
            glyph = SanvyaIcons.add,
            route = "transactions/new",
        ),
        AddAction.Menu.Item(
            key = "receipt",
            label = "Scan bill / receipt",
            glyph = SanvyaIcons.receipt,
            route = "receipts/new",
            locked = !canScan,
        ),
    ),
)
