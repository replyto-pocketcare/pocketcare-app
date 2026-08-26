package com.sanvya.app.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.sp
import com.sanvya.app.theme.LocalSanvyaColors

/**
 * "Are you sure?" -- the port of apps/web/src/ui/Confirm.tsx's dialog.
 *
 * Web reaches it through a `useConfirm()` hook that returns a promise, which
 * has no Compose equivalent: a composable cannot suspend on a dialog it has not
 * drawn yet. The shape here is the same dialog with the caller holding the
 * pending item in state, which is what every other confirm on this platform
 * already does by hand -- there were four hand-rolled AlertDialogs before this
 * one existed.
 *
 * `danger` defaults to true, as it does on web: every caller so far is a
 * delete, and the destructive colour is the half of the dialog that stops
 * someone tapping through it.
 */
@Composable
fun ConfirmDialog(
    title: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    message: String? = null,
    confirmLabel: String,
    cancelLabel: String,
    danger: Boolean = true,
) {
    val colors = LocalSanvyaColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = message?.let { { Text(it, fontSize = 14.sp, color = colors.text2) } },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmLabel, color = if (danger) colors.negative else colors.accent)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(cancelLabel, color = colors.text2) }
        },
    )
}
