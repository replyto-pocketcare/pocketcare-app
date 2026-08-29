package com.sanvya.app.ui.payments

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.domain.upi.isValidVpa
import com.sanvya.app.domain.upi.maskVpa
import com.sanvya.app.domain.upi.normalizeVpa
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.ui.isoLabel

/**
 * "Your UPI ID" -- the body of the Settings card.
 *
 * Ports `apps/web/src/payments/PaymentHandlePanel.tsx`. The heading and the
 * intro paragraph are the card's own title/subtitle in `SettingsScreen`,
 * exactly as web's `<strong>` + muted `<p>` open its `<section>`; what is here
 * is everything underneath.
 *
 * Deliberately honest about the security tier, which is also why the disclosure
 * log is part of this panel rather than a screen of its own: unlike the
 * passphrase-protected personal fields, this value is readable by our server --
 * it has to be, because the point of it is handing it to someone who owes you
 * money. Web's copy says so and lists exactly who has fetched it; so does this.
 *
 * Not to be confused with "Pay anyone", which was struck from the product on
 * 2026-08-29 (docs/mobile/ABSENT-BY-DECISION.md). This panel is about saving
 * and disclosing your OWN handle, and it stays.
 *
 * Mirrors iOS's PaymentHandleSectionView.swift.
 */
@Composable
fun PaymentHandlePanelBody(viewModel: PaymentHandleViewModel = viewModel()) {
    val res = sRes()
    val colors = LocalSanvyaColors.current

    val loading by viewModel.loading.collectAsState()
    val canSave by viewModel.canSave.collectAsState()
    val hint by viewModel.hint.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val error by viewModel.error.collectAsState()
    val disclosures by viewModel.disclosures.collectAsState()

    LaunchedEffect(Unit) { viewModel.start() }

    // rememberSaveable, not remember: a half-typed UPI ID should survive a
    // rotation, and neither value is persisted beyond the saved-instance bundle.
    var value by rememberSaveable { mutableStateOf("") }
    var showLog by rememberSaveable { mutableStateOf(false) }

    val normalized = normalizeVpa(value)
    // Web's `looksValid`: an empty box is not an error, it is just empty.
    val looksValid = normalized.isEmpty() || isValidVpa(normalized)
    val canSubmit = !busy && normalized.isNotEmpty() && isValidVpa(normalized)

    when {
        // Never render the empty form -- or the guest refusal -- before we know.
        // Flashing "add a UPI ID" at someone who has one reads as though it was
        // lost (web's own comment); flashing "create an account" at an account
        // holder reads worse, and web is only spared that by a localStorage
        // session cache the phone has no equivalent of.
        loading -> CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)

        !canSave -> Text(S.Payments.settingsGuestBlocked(res), fontSize = 13.sp, color = colors.text2)

        else -> {
            hint?.let { current ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(S.Payments.settingsCurrent(res), fontSize = 12.sp, color = colors.text2)
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        // Monospace because web renders the mask in a <code>:
                        // the dots and the handle then line up between the saved
                        // value and the "others will see" preview below it.
                        Text(current, fontFamily = FontFamily.Monospace, fontSize = 13.sp, color = colors.text)
                        OutlinedButton(onClick = { viewModel.forget() }, enabled = !busy) {
                            Text(S.Payments.settingsRemove(res))
                        }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    if (hint != null) S.Payments.settingsReplace(res) else S.Payments.settingsLabel(res),
                    fontSize = 12.sp,
                    color = colors.text2,
                )
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    placeholder = { Text(S.Payments.settingsPlaceholder(res)) },
                    singleLine = true,
                    // Web's `aria-invalid={!looksValid}`.
                    isError = !looksValid,
                    // Web sets `inputMode="email"`. A VPA is `name@bank`, so
                    // the email keyboard is the right one: "@" on the first row
                    // and no auto-capitalisation, which is the whole of what
                    // web's `autoComplete="off"` / `spellCheck={false}` buy on a
                    // phone. `normalizeVpa` lower-cases on the way out either
                    // way; this is about what the box looks like while typing.
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Done,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (!looksValid) {
                Text(S.Payments.settingsInvalid(res), fontSize = 12.sp, color = colors.negative)
            }
            if (normalized.isNotEmpty() && looksValid) {
                Text(
                    S.Payments.settingsWillShow(res, maskVpa(normalized)),
                    fontSize = 12.sp,
                    color = colors.text2,
                )
            }

            // The server's own words, verbatim -- see PaymentHandleViewModel.
            error?.let { Text(it, fontSize = 13.sp, color = colors.negative) }

            Button(onClick = { viewModel.save(normalized) { value = "" } }, enabled = canSubmit) {
                // Web puts a Spinner INSIDE the button beside the unchanged
                // label. The colour is named explicitly because the default
                // progress colour is the primary, which on a filled primary
                // button is invisible.
                if (busy) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp,
                    )
                }
                Text(if (hint != null) S.Payments.settingsUpdate(res) else S.Payments.settingsSave(res))
            }

            // The honest bit.
            Text(S.Payments.settingsPrivacy(res), fontSize = 11.5.sp, color = colors.text2)

            if (disclosures.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedButton(onClick = { showLog = !showLog }) {
                        Text(
                            if (showLog) {
                                S.Payments.settingsHideLog(res)
                            } else {
                                S.Payments.settingsShowLog(res, disclosures.size)
                            },
                            fontSize = 11.5.sp,
                        )
                    }
                    if (showLog) {
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            disclosures.forEach { d ->
                                Row(
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    // Null when neither profile table knows this
                                    // viewer -- named HERE, in the user's
                                    // language, rather than in `:data`.
                                    Text(
                                        d.viewerName ?: S.Payments.settingsSomeone(res),
                                        fontSize = 12.5.sp,
                                        color = colors.text2,
                                    )
                                    // Web's `{" \u00B7 "}` separator. A middot is
                                    // punctuation, not copy -- the same glyph in
                                    // all three locales -- so it stays a literal
                                    // rather than becoming a catalogue key.
                                    Text(MID_DOT, fontSize = 12.5.sp, color = colors.text2)
                                    // Web formats `created_at` with the device's
                                    // locale in the device's time zone;
                                    // `isoLabel` reads the date part as the civil
                                    // date the database wrote, which is what
                                    // every other timestamp label in this app
                                    // does. Agreeing with the rest of the app
                                    // beats agreeing with the browser on the one
                                    // day a disclosure lands either side of local
                                    // midnight.
                                    Text(
                                        isoLabel(d.createdAtIso, "d MMM yy"),
                                        fontSize = 12.5.sp,
                                        color = colors.text2,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Web's `{" \u00B7 "}` between a viewer and the date they looked. */
private const val MID_DOT = "\u00B7"
