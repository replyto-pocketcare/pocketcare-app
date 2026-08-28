package com.sanvya.app.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * A plain ISO date input.
 *
 * Web renders `<input type="date">`, which the browser turns into a native
 * picker. Compose has no equivalent primitive, and Material 3's `DatePicker` is
 * a dialog with its own state and its own visual language -- adopting it here
 * would be the first non-web control in the app. Left as text for now and
 * tracked, rather than half-adopted.
 *
 * Was private to `StatementsScreen`; promoted when Groups needed the same
 * control in two more places. Three copies of a date input is how three
 * different date formats end up in one app.
 */
@Composable
fun DateField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
) {
    Column(modifier = modifier) {
        if (label != null) {
            Eyebrow(label)
            Spacer(Modifier.height(4.dp))
        }
        SanvyaInput(
            value = value,
            onValueChange = onValueChange,
            placeholder = ISO_DATE_HINT,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * The shape of a date field, not a translated string.
 *
 * `yyyy-MM-dd` is what every date column stores and what `autoSplitGroupFor`
 * compares against, so the hint is the FORMAT rather than a label -- a
 * localised "Start date" would leave the user guessing which order the parts
 * go in.
 */
const val ISO_DATE_HINT = "YYYY-MM-DD"
