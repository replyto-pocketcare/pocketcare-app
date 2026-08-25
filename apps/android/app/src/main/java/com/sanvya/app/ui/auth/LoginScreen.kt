package com.sanvya.app.ui.auth

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.sanvya.app.R
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.H1
import com.sanvya.app.ui.components.H2
import com.sanvya.app.ui.components.SanvyaButton
import com.sanvya.app.ui.components.SanvyaInput
import com.sanvya.app.ui.components.SanvyaText
import androidx.lifecycle.viewmodel.compose.viewModel

/** Which way in the user is currently using. */
private enum class Mode { Password, Otp }

/**
 * Sign in, or continue as a guest.
 *
 * **Android had no login screen at all** — `AuthViewModel` and a complete
 * `AuthRepository` existed and nothing on screen ever called them, so the app
 * went straight to the dashboard and silently created a guest.
 *
 * Scope is what the repository actually supports, and nothing more:
 * - **Email + password** — `signInWithPassword`. Android's repository has had
 *   this the whole time; iOS's does not, which is why web-registered users can
 *   sign in here and not there (PARITY_AUDIT §6c).
 * - **Email OTP** — `sendOtp` / `verifyOtp`.
 * - **Guest** — `ensureGuest`.
 * - **Google** — `continueWithGoogle`, which links to an existing guest rather
 *   than replacing them. It was absent rather than dead until now, on the rule
 *   that a dead control is worse than a missing one; it is live as of this
 *   change, and the button below does nothing that is not wired.
 */
@Composable
fun LoginScreen(
    onSignedIn: () -> Unit = {},
    viewModel: AuthViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val busy by viewModel.busy.collectAsState()
    val error by viewModel.error.collectAsState()
    val otpSent by viewModel.otpSent.collectAsState()
    val resetStage by viewModel.resetStage.collectAsState()

    // Survives rotation and process death: retyping an email after the keyboard
    // rotated the screen is a small thing that feels like a broken app.
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    var mode by rememberSaveable { mutableStateOf(Mode.Password) }
    var confirmPassword by rememberSaveable { mutableStateOf("") }

    Column(
        modifier = Modifier.fillMaxSize().background(colors.bg).padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        if (resetStage != AuthViewModel.ResetStage.NONE) {
            PasswordResetFlow(
                stage = resetStage,
                viewModel = viewModel,
                email = email,
                onEmailChange = { email = it },
                code = code,
                onCodeChange = { code = it },
                password = password,
                onPasswordChange = { password = it },
                confirmPassword = confirmPassword,
                onConfirmPasswordChange = { confirmPassword = it },
                busy = busy,
                error = error,
                onSignedIn = onSignedIn,
            )
            return@Column
        }

        H1(S.Translation.appName(sRes()), compact = false)
        Spacer(Modifier.padding(top = 8.dp))
        H2(if (otpSent) S.Login.verifyTitle(sRes()) else S.Login.signinTitle(sRes()))
        SanvyaText(
            if (otpSent) S.Login.sentCode(sRes(), email) else S.Login.signinSub(sRes()),
            style = SanvyaType.statLabel,
            color = colors.text2,
            modifier = Modifier.padding(top = 6.dp, bottom = 18.dp),
        )

        if (otpSent) {
            SanvyaInput(
                value = code,
                onValueChange = { code = it },
                placeholder = S.Login.codePlaceholder(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 10.dp))
            SanvyaButton(
                onClick = { viewModel.verifyOtp(email, code, onSignedIn) },
                enabled = !busy && code.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaText(
                    if (busy) S.Login.verifying(sRes()) else S.Login.verifyCode(sRes()),
                    style = SanvyaType.button,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SanvyaButton(onClick = { viewModel.sendOtp(email) }, enabled = !busy, ghost = true) {
                    SanvyaText(S.Login.resend(sRes()), style = SanvyaType.button)
                }
                Spacer(Modifier.weight(1f))
                SanvyaButton(onClick = { viewModel.backToEmail(); code = "" }, ghost = true) {
                    SanvyaText(S.Login.backToSignin(sRes()), style = SanvyaType.button)
                }
            }
        } else {
            SanvyaInput(
                value = email,
                onValueChange = { email = it },
                placeholder = S.Login.emailLabel(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )

            if (mode == Mode.Password) {
                Spacer(Modifier.padding(top = 10.dp))
                SanvyaInput(
                    value = password,
                    onValueChange = { password = it },
                    placeholder = S.Login.passwordPlaceholder(sRes()),
                    enabled = !busy,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.padding(top = 10.dp))
            SanvyaButton(
                onClick = {
                    if (mode == Mode.Password) {
                        viewModel.signInWithPassword(email, password, onSignedIn)
                    } else {
                        viewModel.sendOtp(email)
                    }
                },
                // Not validating the address here: Supabase decides whether an
                // email is real, and a second opinion in the UI is only ever
                // wrong in a way the user cannot argue with.
                enabled = !busy && email.isNotBlank() &&
                    (mode == Mode.Otp || password.isNotBlank()),
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaText(
                    when {
                        busy -> S.Login.saving(sRes())
                        mode == Mode.Password -> S.Login.signInBtn(sRes())
                        else -> S.Login.`continue`(sRes())
                    },
                    style = SanvyaType.button,
                )
            }

            if (mode == Mode.Password) {
                SanvyaButton(
                    onClick = { viewModel.startPasswordReset() },
                    ghost = true,
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                ) {
                    SanvyaText(S.Login.forgotPassword(sRes()), style = SanvyaType.button)
                }
            }

            SanvyaButton(
                onClick = {
                    mode = if (mode == Mode.Password) Mode.Otp else Mode.Password
                    viewModel.clearError()
                },
                ghost = true,
                modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            ) {
                SanvyaText(
                    if (mode == Mode.Password) S.Login.`continue`(sRes()) else S.Login.signInBtn(sRes()),
                    style = SanvyaType.button,
                )
            }
        }

        error?.let {
            SanvyaText(it, style = SanvyaType.statLabel, color = colors.negative,
                modifier = Modifier.padding(top = 12.dp))
        }

        SanvyaText(
            S.Login.or(sRes()),
            style = SanvyaType.statLabel,
            color = colors.text3,
            modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp),
        )

        // Google. Not gated on `mode`, because it is neither a sign-in nor a
        // sign-up from the user's side -- web shows it in both modes and only
        // changes the label, which is what the two keys below are for.
        SanvyaButton(
            onClick = { viewModel.continueWithGoogle() },
            enabled = !busy,
            ghost = true,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Image(
                    painter = painterResource(R.drawable.ic_google),
                    // Decorative: the label right next to it already says
                    // "Continue with Google", so announcing the mark as well
                    // would read the same thing twice.
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.padding(start = 10.dp))
                SanvyaText(S.Login.continueGoogle(sRes()), style = SanvyaType.button)
            }
        }

        Spacer(Modifier.padding(top = 8.dp))

        SanvyaButton(
            onClick = { viewModel.ensureGuest(onSignedIn) },
            enabled = !busy,
            ghost = true,
            modifier = Modifier.fillMaxWidth(),
        ) {
            SanvyaText(S.Onboarding.tryGuest(sRes()), style = SanvyaType.button)
        }
    }
}


/**
 * Password reset — send a code, verify it, choose a new password.
 *
 * Ported from login/page.tsx's `startReset` / `verifyAndFinish` (the
 * `otpType === "recovery"` branch) / `setNewPassword`. Absent on both native
 * platforms until now: a web-registered user who forgot their password had no
 * way through on a phone.
 *
 * It takes over the whole screen rather than sitting under the sign-in form.
 * Three steps stacked below a sign-in form is the "scroll inside a dialog"
 * problem in a different costume.
 */
@Composable
private fun PasswordResetFlow(
    stage: AuthViewModel.ResetStage,
    viewModel: AuthViewModel,
    email: String,
    onEmailChange: (String) -> Unit,
    code: String,
    onCodeChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    confirmPassword: String,
    onConfirmPasswordChange: (String) -> Unit,
    busy: Boolean,
    error: String?,
    onSignedIn: () -> Unit,
) {
    val colors = LocalSanvyaColors.current

    H2(
        if (stage == AuthViewModel.ResetStage.NEW_PASSWORD) S.Login.newPwTitle(sRes())
        else S.Login.resetTitle(sRes()),
    )
    SanvyaText(
        when (stage) {
            AuthViewModel.ResetStage.EMAIL -> S.Login.resetSub(sRes())
            // Deliberately the "if an account exists" wording, not a
            // confirmation that one does -- see Auth.kt's sendPasswordReset.
            AuthViewModel.ResetStage.CODE -> S.Login.sentReset(sRes(), email)
            else -> S.Login.setNewPwDefault(sRes())
        },
        style = SanvyaType.statLabel,
        color = colors.text2,
        modifier = Modifier.padding(top = 6.dp, bottom = 18.dp),
    )

    when (stage) {
        AuthViewModel.ResetStage.EMAIL -> {
            SanvyaInput(
                value = email,
                onValueChange = onEmailChange,
                placeholder = S.Login.emailLabel(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 10.dp))
            SanvyaButton(
                onClick = { viewModel.sendPasswordReset(email) },
                enabled = !busy && email.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaText(
                    if (busy) S.Login.saving(sRes()) else S.Login.sendResetCode(sRes()),
                    style = SanvyaType.button,
                )
            }
        }

        AuthViewModel.ResetStage.CODE -> {
            SanvyaInput(
                value = code,
                onValueChange = onCodeChange,
                placeholder = S.Login.codePlaceholder(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 10.dp))
            SanvyaButton(
                onClick = { viewModel.verifyPasswordResetCode(email, code) },
                enabled = !busy && code.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaText(
                    if (busy) S.Login.verifying(sRes()) else S.Login.verifyCode(sRes()),
                    style = SanvyaType.button,
                )
            }
        }

        else -> {
            SanvyaInput(
                value = password,
                onValueChange = onPasswordChange,
                placeholder = S.Login.newPw(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 10.dp))
            SanvyaInput(
                value = confirmPassword,
                onValueChange = onConfirmPasswordChange,
                placeholder = S.Login.confirmNewPw(sRes()),
                enabled = !busy,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation(),
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.padding(top = 10.dp))
            SanvyaButton(
                onClick = { viewModel.setPassword(password, onSignedIn) },
                // Both rules are web's, checked here so the user is told before
                // a round trip rather than after one.
                enabled = !busy && password.length >= MIN_PASSWORD_LENGTH && password == confirmPassword,
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaText(
                    if (busy) S.Login.saving(sRes()) else S.Login.updatePw(sRes()),
                    style = SanvyaType.button,
                )
            }
            // Web validates on submit and shows one message; showing it live
            // under the field is the same information, sooner.
            if (password.isNotEmpty() && password.length < MIN_PASSWORD_LENGTH) {
                SanvyaText(
                    S.Login.errPwLen(sRes()),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                    modifier = Modifier.padding(top = 8.dp),
                )
            } else if (confirmPassword.isNotEmpty() && password != confirmPassword) {
                SanvyaText(
                    S.Login.errPwMatch(sRes()),
                    style = SanvyaType.statLabel,
                    color = colors.text2,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        }
    }

    error?.let {
        SanvyaText(
            it,
            style = SanvyaType.statLabel,
            color = colors.negative,
            modifier = Modifier.padding(top = 12.dp),
        )
    }

    SanvyaButton(
        onClick = { viewModel.cancelPasswordReset() },
        ghost = true,
        modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
    ) {
        SanvyaText(S.Login.backToSignin(sRes()), style = SanvyaType.button)
    }
}

/** Web's `password.length < 8` check, named rather than inline. */
private const val MIN_PASSWORD_LENGTH = 8
