package com.sanvya.app.ui.security

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sanvya.app.data.repository.SecurityRepository
import com.sanvya.app.data.repository.SupportGrant
import com.sanvya.app.domain.security.SecurityStatus
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * Security & encryption — the body of the Settings card.
 *
 * Ports `apps/web/src/crypto/SecurityPanel.tsx`. The heading and the intro
 * paragraph are the card's own title/subtitle in SettingsScreen, exactly as
 * web's `<h2>` + `<p class="muted">` sit at the top of its `<section>`; what
 * is here is the four-state body underneath.
 *
 * The panel deliberately has no "hide encryption" affordance and no way to
 * change a passphrase, because web has neither. Both are real gaps; inventing
 * them on the phone would put the two clients in different states with no way
 * for a user to get back.
 */
@Composable
fun SecurityPanelBody(viewModel: SecurityViewModel = viewModel()) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val status by viewModel.status.collectAsState()
    val recoveryCode by viewModel.recoveryCode.collectAsState()

    LaunchedEffect(Unit) { viewModel.start() }

    // WEB'S RECOVERY CODE NEVER RENDERS, AND THIS PORT'S DOES.
    //
    // SecurityPanel.tsx picks its branch on `status` alone, and `setupEncryption()`
    // flips `hasKeys` to true and calls `notify()` BEFORE it returns the code. By
    // the time `SetupBox` runs `setRecovery(code)`, React has already re-rendered
    // the panel into `<UnlockedBox/>` and unmounted the component holding that
    // state. The one-time recovery code -- the only way back in if the passphrase is
    // forgotten -- is displayed to nobody.
    //
    // SECURITY_ENCRYPTION_PLAN.md's own last line says "The UI must make the
    // recovery code impossible to skip at setup". So this branch is checked FIRST,
    // ahead of the status machine, and the panel stays on it until the user
    // acknowledges. Reproducing web's rendering here would mean shipping a feature
    // whose failure mode is permanently unreadable user data. Reported, not fixed in
    // apps/web.
    when {
        recoveryCode != null -> RecoveryCodeBox(code = recoveryCode!!, viewModel = viewModel)
        status == SecurityStatus.LOADING -> Text(
            S.Security.checking(res),
            fontSize = 13.sp,
            color = colors.text2,
        )
        status == SecurityStatus.UNSET -> SetupBox(viewModel)
        status == SecurityStatus.LOCKED -> UnlockBox(viewModel)
        else -> UnlockedBox(viewModel)
    }
}

@Composable
private fun SetupBox(viewModel: SecurityViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val busy by viewModel.busy.collectAsState()
    val errorKey by viewModel.errorKey.collectAsState()
    // rememberSaveable, not remember: a passphrase half-typed when the keyboard
    // rotates the activity should survive, and neither value is ever persisted
    // beyond the saved-instance bundle.
    var passphrase by rememberSaveable { mutableStateOf("") }
    var confirm by rememberSaveable { mutableStateOf("") }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Tinted(background = colors.surface2, border = colors.border) {
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        append(S.Security.setupNoteBold(res))
                    }
                    append(S.Security.setupNoteMid(res))
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        append(S.Security.setupNoteBoth(res))
                    }
                    append(S.Security.setupNoteEnd(res))
                },
                fontSize = 12.5.sp,
                color = colors.text,
            )
        }
        OutlinedTextField(
            value = passphrase,
            onValueChange = { passphrase = it; viewModel.clearError() },
            label = { Text(S.Security.passphrasePlaceholder(res)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = confirm,
            onValueChange = { confirm = it; viewModel.clearError() },
            label = { Text(S.Security.confirmPlaceholder(res)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { viewModel.setup(passphrase, confirm) }),
            modifier = Modifier.fillMaxWidth(),
        )
        errorKey?.let { Text(securityMessage(it), fontSize = 13.sp, color = colors.negative) }
        Button(
            onClick = { viewModel.setup(passphrase, confirm) },
            // Web: `disabled={busy || !pass}` -- the confirm field is checked
            // on submit, not by disabling the button, so the mismatch message
            // is reachable.
            enabled = !busy && passphrase.isNotEmpty(),
        ) {
            Text(if (busy) S.Security.setupBusy(res) else S.Security.setupCta(res))
        }
    }
}

@Composable
private fun RecoveryCodeBox(code: String, viewModel: SecurityViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Tinted(background = colors.accentGhost, border = colors.accentSoft) {
            Text(S.Security.recoveryTitle(res), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = colors.text)
            Text(S.Security.recoveryHint(res), fontSize = 12.sp, color = colors.text2)
            // SelectionContainer is the closest thing Compose has to web's
            // `userSelect: "all"`. The copy button beside it exists because
            // long-press-and-drag over a 24-character code on a phone is a
            // worse experience than web's double-click, and losing this code
            // is unrecoverable -- see the warning right below it.
            SelectionContainer {
                Text(
                    code,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 16.sp,
                    letterSpacing = 0.06.em,
                    color = colors.text,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(colors.surface, RoundedCornerShape(8.dp))
                        .border(1.dp, colors.border, RoundedCornerShape(8.dp))
                        .padding(horizontal = 10.dp, vertical = 8.dp),
                )
            }
            TextButton(onClick = { clipboard.setText(AnnotatedString(code)); copied = true }) {
                Text(
                    if (copied) S.Security.codeCopied(res) else S.Security.copyCode(res),
                    fontSize = 13.sp,
                    color = colors.accent,
                )
            }
        }
        Tinted(background = colors.surface2, border = colors.negative) {
            Text(S.Security.recoveryWarnTitle(res), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = colors.negative)
            Text(
                buildAnnotatedString {
                    val bold = SpanStyle(fontWeight = FontWeight.Bold)
                    append(S.Security.recoveryWarnOne(res))
                    withStyle(bold) { append(S.Security.recoveryWarnKeys(res)) }
                    append(S.Security.recoveryWarnTwo(res))
                    withStyle(bold) { append(S.Security.recoveryWarnForget(res)) }
                    append(S.Security.recoveryWarnThree(res))
                    withStyle(bold) { append(S.Security.recoveryWarnUnrecoverable(res)) }
                    append(S.Security.recoveryWarnFour(res))
                    withStyle(bold) { append(S.Security.recoveryWarnSupport(res)) }
                    append(S.Security.recoveryWarnFive(res))
                },
                fontSize = 12.5.sp,
                color = colors.text,
            )
        }
        Button(onClick = { viewModel.acknowledgeRecoveryCode() }) {
            Text(S.Security.recoveryAck(res))
        }
    }
}

@Composable
private fun UnlockBox(viewModel: SecurityViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val busy by viewModel.busy.collectAsState()
    val errorKey by viewModel.errorKey.collectAsState()
    var secret by rememberSaveable { mutableStateOf("") }
    var useRecovery by rememberSaveable { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(S.Security.unlockIntro(res), fontSize = 13.sp, color = colors.text2)
        OutlinedTextField(
            value = secret,
            onValueChange = { secret = it; viewModel.clearError() },
            label = {
                Text(
                    if (useRecovery) S.Security.recoveryCodeLabel(res) else S.Security.passphraseLabel(res),
                )
            },
            singleLine = true,
            // The recovery code is transcribed off paper, so masking it turns a
            // 24-character copy into a guess. Web shows both as `type="password"`
            // because a browser has no other affordance; a phone keyboard makes
            // the distinction worth drawing.
            visualTransformation = if (useRecovery) {
                VisualTransformation.None
            } else {
                PasswordVisualTransformation()
            },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { viewModel.unlock(secret, useRecovery) }),
            modifier = Modifier.fillMaxWidth(),
        )
        errorKey?.let { Text(securityMessage(it), fontSize = 13.sp, color = colors.negative) }
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(onClick = { viewModel.unlock(secret, useRecovery) }, enabled = !busy && secret.isNotEmpty()) {
                Text(if (busy) S.Security.unlockBusy(res) else S.Security.unlock(res))
            }
            OutlinedButton(
                onClick = {
                    useRecovery = !useRecovery
                    secret = ""
                    viewModel.clearError()
                },
            ) {
                Text(if (useRecovery) S.Security.usePassphrase(res) else S.Security.useRecovery(res))
            }
        }
    }
}

@Composable
private fun UnlockedBox(viewModel: SecurityViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                S.Security.unlockedStatus(res),
                fontSize = 14.sp,
                color = colors.positive,
                modifier = Modifier.padding(end = 8.dp),
            )
            OutlinedButton(onClick = { viewModel.lock() }) { Text(S.Security.lock(res)) }
        }
        HorizontalDivider()
        SupportAccess(viewModel)
    }
}

@Composable
private fun SupportAccess(viewModel: SecurityViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    val busy by viewModel.busy.collectAsState()
    val grants by viewModel.grants.collectAsState()
    val issued by viewModel.grantIssued.collectAsState()
    val grantErrorKey by viewModel.grantErrorKey.collectAsState()

    Tinted(background = colors.surface2, border = colors.border) {
        Text(S.Security.supportTitle(res), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = colors.text)
        Text(
            buildAnnotatedString {
                append(S.Security.supportBodyOne(res))
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(S.Security.supportBodyHours(res)) }
                append(S.Security.supportBodyTwo(res))
            },
            fontSize = 12.sp,
            color = colors.text2,
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = { viewModel.issueGrant(SecurityRepository.GRANT_SCOPE_STRUCTURAL) },
                enabled = !busy,
            ) { Text(S.Security.allowSyncCheck(res)) }
            OutlinedButton(
                onClick = { viewModel.issueGrant(SecurityRepository.GRANT_SCOPE_CONTENT) },
                enabled = !busy,
            ) { Text(S.Security.allowDataAccess(res)) }
        }
        if (busy) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
        }
        issued?.let {
            Text(
                S.Security.grantedUntil(res, scopeWord(it.scope), localTimeLabel(it.expiresAtIso)),
                fontSize = 12.sp,
                color = colors.text2,
            )
        }
        grantErrorKey?.let { Text(securityMessage(it), fontSize = 12.sp, color = colors.negative) }
        grants.forEach { grant -> GrantRow(grant, viewModel) }
    }
}

@Composable
private fun GrantRow(grant: SupportGrant, viewModel: SecurityViewModel) {
    val res = sRes()
    val colors = LocalSanvyaColors.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            S.Security.grantExpires(res, grantLabel(grant.scope), localTimeLabel(grant.expiresAtIso)),
            fontSize = 12.sp,
            color = colors.text,
        )
        OutlinedButton(onClick = { viewModel.revokeGrant(grant.id) }) {
            Text(S.Security.revoke(res), fontSize = 12.sp)
        }
    }
}

/** The tinted sub-card web draws with `className="card"` and a background. */
@Composable
private fun Tinted(
    background: Color,
    border: Color,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(background, RoundedCornerShape(10.dp))
            .border(1.dp, border, RoundedCornerShape(10.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/**
 * An i18n key from the repository or the view model, resolved.
 *
 * A `when` rather than a reflective lookup: the generated accessors are what
 * make a renamed key a compile error, and a map keyed by string would throw
 * that away for the one place it matters most.
 */
@Composable
private fun securityMessage(key: String): String {
    val res = sRes()
    return when (key) {
        "setupTooShort" -> S.Security.setupTooShort(res)
        "setupMismatch" -> S.Security.setupMismatch(res)
        "setupFailed" -> S.Security.setupFailed(res)
        "alreadySetUp" -> S.Security.alreadySetUp(res)
        "wrongPassphrase" -> S.Security.wrongPassphrase(res)
        "invalidRecovery" -> S.Security.invalidRecovery(res)
        "notSetUp" -> S.Security.notSetUp(res)
        "noRecoveryKey" -> S.Security.noRecoveryKey(res)
        "unlockForContent" -> S.Security.unlockForContent(res)
        "supportNotConfigured" -> S.Security.supportNotConfigured(res)
        "unlockToAuthorize" -> S.Security.unlockToAuthorize(res)
        "grantFailed" -> S.Security.grantFailed(res)
        else -> S.Security.notSignedIn(res)
    }
}

/** The lowercase word web interpolates into "Granted {scope} access until …". */
@Composable
private fun scopeWord(scope: String): String {
    val res = sRes()
    return if (scope == SecurityRepository.GRANT_SCOPE_CONTENT) {
        S.Security.scopeContent(res)
    } else {
        S.Security.scopeStructural(res)
    }
}

/** Web's `g.scope === "content" ? "Data access" : "Sync check"`. */
@Composable
private fun grantLabel(scope: String): String {
    val res = sRes()
    return if (scope == SecurityRepository.GRANT_SCOPE_CONTENT) {
        S.Security.grantRowContent(res)
    } else {
        S.Security.grantRowStructural(res)
    }
}

/**
 * Web's `new Date(x).toLocaleTimeString()` — no options, so the platform's
 * MEDIUM time (which includes seconds), not SHORT.
 *
 * Two parsers because `expires_at` is a Postgres `timestamptz` and what
 * PowerSync lands in SQLite depends on how PostgREST rendered it; the ISO the
 * client itself wrote parses as an `Instant`, a server-rendered offset does
 * not. Falling back to the raw string beats rendering an empty cell for a
 * grant the user may want to revoke.
 */
private fun localTimeLabel(iso: String): String {
    val formatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.MEDIUM)
    return runCatching {
        OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.systemDefault()).format(formatter)
    }.recoverCatching {
        Instant.parse(iso).atZone(ZoneId.systemDefault()).format(formatter)
    }.getOrDefault(iso)
}
