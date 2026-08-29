import Data
import Domain
import SwiftUI
import UIKit

/**
 Security & encryption — the Settings form's section.

 Ports `apps/web/src/crypto/SecurityPanel.tsx`. The heading and the intro
 paragraph are the section's header and footer, which is exactly the `<h2>` +
 muted `<p>` web opens its `<section>` with; what is inside is the four-state
 body underneath.

 The panel deliberately has no "turn encryption off" affordance and no way to
 change a passphrase, because web has neither. Both are real gaps; inventing
 them on the phone would put the two clients in different states with no way
 for a user to get back.

 Mirrors Android's SecurityPanel.kt.
 */
struct SecurityPanelSection: View {

    @State private var viewModel = SecurityViewModel()
    @State private var passphrase = ""
    @State private var confirm = ""
    @State private var unlockSecret = ""
    @State private var useRecovery = false
    @State private var copied = false

    var body: some View {
        Section(header: Text(S.Security.title), footer: Text(S.Security.intro)) {
            // One Group, so the `.task` below keeps its identity as the state
            // machine switches branches and the 30-second grant poll is not
            // restarted every time something changes.
            Group {
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
                if let code = viewModel.recoveryCode {
                    recoveryBox(code)
                } else if viewModel.status == SecurityStatus.loading {
                    Text(S.Security.checking).font(.footnote).foregroundStyle(Color.text2)
                } else if viewModel.status == SecurityStatus.unset {
                    setupBox
                } else if viewModel.status == SecurityStatus.locked {
                    unlockBox
                } else {
                    unlockedBox
                }
            }
            .task { await viewModel.start() }
        }
    }

    // MARK: - Setup

    @ViewBuilder
    private var setupBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            (
                Text(S.Security.setupNoteBold).bold()
                    + Text(S.Security.setupNoteMid)
                    + Text(S.Security.setupNoteBoth).bold()
                    + Text(S.Security.setupNoteEnd)
            )
            .font(.footnote)
            .foregroundStyle(Color.text)
        }
        SecureField(S.Security.passphrasePlaceholder, text: $passphrase)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: passphrase) { _, _ in viewModel.clearError() }
        SecureField(S.Security.confirmPlaceholder, text: $confirm)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: confirm) { _, _ in viewModel.clearError() }
        if let key = viewModel.errorKey {
            Text(securityMessage(key)).font(.footnote).foregroundStyle(Color.negative)
        }
        Button {
            Task { await viewModel.setup(passphrase: passphrase, confirm: confirm) }
        } label: {
            Text(viewModel.busy ? S.Security.setupBusy : S.Security.setupCta)
        }
        // Web: `disabled={busy || !pass}` -- the confirm field is checked on
        // submit, not by disabling the button, so the mismatch message is
        // reachable.
        .disabled(viewModel.busy || passphrase.isEmpty)
    }

    // MARK: - Recovery code

    @ViewBuilder
    private func recoveryBox(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(S.Security.recoveryTitle).font(.subheadline.bold()).foregroundStyle(Color.text)
            Text(S.Security.recoveryHint).font(.caption).foregroundStyle(Color.text2)
            // `.textSelection(.enabled)` is the closest thing SwiftUI has to
            // web's `userSelect: "all"`. The copy button beside it exists
            // because long-pressing a 24-character code on a phone is a worse
            // experience than web's double-click, and losing this code is
            // unrecoverable -- see the warning right below it.
            Text(code)
                .font(.system(.body, design: .monospaced))
                .kerning(1)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border, lineWidth: 1))
            Button {
                UIPasteboard.general.string = code
                copied = true
            } label: {
                Text(copied ? S.Security.codeCopied : S.Security.copyCode)
                    .font(.footnote)
                    .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 6) {
            Text(S.Security.recoveryWarnTitle).font(.subheadline.bold()).foregroundStyle(Color.negative)
            (
                Text(S.Security.recoveryWarnOne)
                    + Text(S.Security.recoveryWarnKeys).bold()
                    + Text(S.Security.recoveryWarnTwo)
                    + Text(S.Security.recoveryWarnForget).bold()
                    + Text(S.Security.recoveryWarnThree)
                    + Text(S.Security.recoveryWarnUnrecoverable).bold()
                    + Text(S.Security.recoveryWarnFour)
                    + Text(S.Security.recoveryWarnSupport).bold()
                    + Text(S.Security.recoveryWarnFive)
            )
            .font(.footnote)
            .foregroundStyle(Color.text)
        }
        .padding(.vertical, 4)

        Button(S.Security.recoveryAck) { viewModel.acknowledgeRecoveryCode() }
    }

    // MARK: - Unlock

    @ViewBuilder
    private var unlockBox: some View {
        Text(S.Security.unlockIntro).font(.footnote).foregroundStyle(Color.text2)
        // The recovery code is transcribed off paper, so masking it turns a
        // 24-character copy into a guess. Web shows both as `type="password"`
        // because a browser has no other affordance; a phone keyboard makes the
        // distinction worth drawing.
        if useRecovery {
            TextField(S.Security.recoveryCodeLabel, text: $unlockSecret)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit { Task { await viewModel.unlock(secret: unlockSecret, useRecovery: true) } }
                .onChange(of: unlockSecret) { _, _ in viewModel.clearError() }
        } else {
            SecureField(S.Security.passphraseLabel, text: $unlockSecret)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await viewModel.unlock(secret: unlockSecret, useRecovery: false) } }
                .onChange(of: unlockSecret) { _, _ in viewModel.clearError() }
        }
        if let key = viewModel.errorKey {
            Text(securityMessage(key)).font(.footnote).foregroundStyle(Color.negative)
        }
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.unlock(secret: unlockSecret, useRecovery: useRecovery) }
            } label: {
                Text(viewModel.busy ? S.Security.unlockBusy : S.Security.unlock)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.busy || unlockSecret.isEmpty)

            Button {
                useRecovery.toggle()
                unlockSecret = ""
                viewModel.clearError()
            } label: {
                Text(useRecovery ? S.Security.usePassphrase : S.Security.useRecovery)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Unlocked

    @ViewBuilder
    private var unlockedBox: some View {
        HStack {
            Text(S.Security.unlockedStatus).font(.subheadline).foregroundStyle(Color.positive)
            Spacer(minLength: 8)
            Button(S.Security.lock) { viewModel.lock() }.buttonStyle(.bordered)
        }
        supportAccess
    }

    @ViewBuilder
    private var supportAccess: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(S.Security.supportTitle).font(.subheadline.bold()).foregroundStyle(Color.text)
            (
                Text(S.Security.supportBodyOne)
                    + Text(S.Security.supportBodyHours).bold()
                    + Text(S.Security.supportBodyTwo)
            )
            .font(.caption)
            .foregroundStyle(Color.text2)
            HStack(spacing: 8) {
                Button(S.Security.allowSyncCheck) {
                    Task { await viewModel.issueGrant(scope: SecurityGrantScope.structural) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.busy)
                Button(S.Security.allowDataAccess) {
                    Task { await viewModel.issueGrant(scope: SecurityGrantScope.content) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.busy)
            }
            if viewModel.busy { ProgressView() }
            if let issued = viewModel.grantIssued {
                Text(
                    S.Security.grantedUntil(
                        scope: scopeWord(issued.scope),
                        time: localTimeLabel(issued.expiresAtIso)
                    )
                )
                .font(.caption)
                .foregroundStyle(Color.text2)
            }
            if let key = viewModel.grantErrorKey {
                Text(securityMessage(key)).font(.caption).foregroundStyle(Color.negative)
            }
        }
        .padding(.vertical, 4)

        ForEach(viewModel.grants) { grant in
            HStack {
                Text(
                    S.Security.grantExpires(
                        label: grantLabel(grant.scope),
                        time: localTimeLabel(grant.expiresAtIso)
                    )
                )
                .font(.caption)
                Spacer(minLength: 8)
                Button(S.Security.revoke) { Task { await viewModel.revokeGrant(id: grant.id) } }
                    .buttonStyle(.bordered)
                    .font(.caption)
            }
        }
    }
}

/**
 An i18n key from the repository or the view model, resolved.

 A `switch` rather than a reflective lookup: the generated accessors are what
 make a renamed key a compile error, and a map keyed by string would throw that
 away for the one place it matters most.
 */
private func securityMessage(_ key: String) -> String {
    switch key {
    case "setupTooShort": return S.Security.setupTooShort
    case "setupMismatch": return S.Security.setupMismatch
    case "setupFailed": return S.Security.setupFailed
    case "alreadySetUp": return S.Security.alreadySetUp
    case "wrongPassphrase": return S.Security.wrongPassphrase
    case "invalidRecovery": return S.Security.invalidRecovery
    case "notSetUp": return S.Security.notSetUp
    case "noRecoveryKey": return S.Security.noRecoveryKey
    case "unlockForContent": return S.Security.unlockForContent
    case "supportNotConfigured": return S.Security.supportNotConfigured
    case "unlockToAuthorize": return S.Security.unlockToAuthorize
    case "grantFailed": return S.Security.grantFailed
    default: return S.Security.notSignedIn
    }
}

/// The lowercase word web interpolates into "Granted {scope} access until …".
private func scopeWord(_ scope: String) -> String {
    scope == SecurityGrantScope.content ? S.Security.scopeContent : S.Security.scopeStructural
}

/// Web's `g.scope === "content" ? "Data access" : "Sync check"`.
private func grantLabel(_ scope: String) -> String {
    scope == SecurityGrantScope.content ? S.Security.grantRowContent : S.Security.grantRowStructural
}

/**
 Web's `new Date(x).toLocaleTimeString()` — no options, so the platform's
 medium time (which includes seconds), not short.

 `parseOccurredAt` (TransactionsViewModel.swift) already handles both ISO
 shapes this app and PostgREST produce; an unparseable timestamp renders as
 itself rather than as an empty cell beside a grant the user may want to
 revoke.
 */
private func localTimeLabel(_ iso: String) -> String {
    guard let date = parseOccurredAt(iso) else { return iso }
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}
