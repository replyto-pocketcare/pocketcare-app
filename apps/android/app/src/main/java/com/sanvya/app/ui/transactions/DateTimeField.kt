package com.sanvya.app.ui.transactions

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val DISPLAY_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy, HH:mm")

/**
 * Date+time picker for the transaction forms -- matches transactions/new
 * and .../[id]/edit's `<input type="datetime-local">`. Material3 has no
 * built-in TimePickerDialog (only DatePickerDialog), so the time step is a
 * plain TimePicker wrapped in an AlertDialog, chained after the date step.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateTimeField(value: LocalDateTime, onChange: (LocalDateTime) -> Unit, label: String = "Date") {
    // rememberSaveable: keeps the picker dialogs open (and the in-progress
    // date pick, mid-flow between the date and time steps) across a
    // configuration change -- see docs/plans/native-mobile-apps.md's R1 /
    // LIFE-2 ("dialogs stay open"), retrofitted 2026-08-06 (P3.19).
    // LocalDateTime is Serializable, so the default saver handles it.
    var showDatePicker by rememberSaveable { mutableStateOf(false) }
    var showTimePicker by rememberSaveable { mutableStateOf(false) }
    var pendingDate by rememberSaveable { mutableStateOf(value) }

    OutlinedTextField(
        value = value.format(DISPLAY_FORMAT),
        onValueChange = {},
        readOnly = true,
        label = { Text(label) },
        modifier = Modifier.padding(bottom = 0.dp),
        trailingIcon = {
            TextButton(onClick = { showDatePicker = true }) { Text("Change") }
        },
    )

    if (showDatePicker) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = value.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    val millis = state.selectedDateMillis
                    if (millis != null) {
                        val picked = Instant.ofEpochMilli(millis).atZone(ZoneId.of("UTC")).toLocalDate()
                        pendingDate = LocalDateTime.of(picked, value.toLocalTime())
                    }
                    showDatePicker = false
                    showTimePicker = true
                }) { Text("Next") }
            },
            dismissButton = { TextButton(onClick = { showDatePicker = false }) { Text("Cancel") } },
        ) {
            DatePicker(state = state)
        }
    }

    if (showTimePicker) {
        val timeState = rememberTimePickerState(
            initialHour = pendingDate.hour,
            initialMinute = pendingDate.minute,
            is24Hour = true,
        )
        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    onChange(pendingDate.withHour(timeState.hour).withMinute(timeState.minute))
                    showTimePicker = false
                }) { Text("Done") }
            },
            dismissButton = { TextButton(onClick = { showTimePicker = false }) { Text("Cancel") } },
            text = {
                Column { TimePicker(state = timeState) }
            },
        )
    }
}
