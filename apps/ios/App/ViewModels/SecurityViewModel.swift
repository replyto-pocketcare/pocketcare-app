import Data
import Domain
import Factory
import Foundation

/// A grant that was just issued, so the panel can say until when.
struct GrantIssuedNotice: Sendable, Equatable {
    let scope: String
    let expiresAtIso: String
}

/**
 The Security & encryption panel's state.

 Ports `apps/web/src/crypto/SecurityPanel.tsx` — the component, not the crypto:
 every key operation belongs to `SecurityRepository`, and everything here is the
 four-state machine web renders (`loading` / `unset` / `locked` / `unlocked`)
 plus the two forms that drive it.

 Every message this exposes is an i18n KEY, never a sentence. Web can throw
 `new Error("Wrong passphrase.")` and render `e.message` because its copy is
 English in the source; a translated app cannot, so the key travels and the
 view resolves it against the `security` catalogue.

 Mirrors Android's SecurityViewModel.
 */
@Observable
@MainActor
final class SecurityViewModel {

    @ObservationIgnored
    @Injected(\.securityRepository) private var securityRepository

    /// Web's `useCryptoStatus()`.
    private(set) var status: String = SecurityStatus.loading
    private(set) var busy = false
    /// i18n key in the `security` namespace, or nil.
    private(set) var errorKey: String?

    /**
     The one-time recovery code, held only until the user acknowledges it.

     Non-nil is its own screen on web — the setup form is replaced by the code
     and the "there is no other way back in" warning, and there is no way past
     it except the acknowledge button.
     */
    private(set) var recoveryCode: String?

    private(set) var grants: [SupportGrant] = []
    private(set) var grantIssued: GrantIssuedNotice?
    private(set) var grantErrorKey: String?

    /**
     Web's `useEffect(() => { void refreshKeyState(); }, [])`, plus the grant
     poll its `SupportAccess` runs on a 30-second interval so a grant that has
     expired stops being offered for revocation.

     Driven by the view's `.task`, so it is cancelled when the panel goes away
     rather than polling behind a screen nobody is looking at.

     `refreshKeyState()` is INSIDE the loop and INSIDE a `try?`, and both halves
     of that matter. Unguarded, a throw from the local `user_keys` read on a
     cold start would propagate out of this task and the poll below would never
     start, leaving `status` at `loading` for the life of the screen. Inside the
     loop, a first attempt that failed because the device was offline is retried
     every thirty seconds instead of leaving the panel stuck on "Checking…"
     until the user navigates away and back. The repository does the network
     probe only while the answer is still unknown, so the retry costs one local
     query once it has settled.
     */
    func start() async {
        while !Task.isCancelled {
            try? await securityRepository.refreshKeyState()
            refreshStatus()
            grants = (try? await securityRepository.activeGrants()) ?? []
            try? await Task.sleep(nanoseconds: grantPollNanos)
        }
    }

    private func refreshStatus() {
        let snapshot = securityRepository.snapshot()
        status = securityStatus(hasKeys: snapshot.hasKeys, unlocked: snapshot.unlocked)
    }

    // MARK: - Setup

    func setup(passphrase: String, confirm: String) async {
        errorKey = passphraseSetupErrorKey(passphrase: passphrase, confirm: confirm)
        if errorKey != nil { return }
        busy = true
        defer { busy = false }
        do {
            recoveryCode = try await securityRepository.setupEncryption(passphrase: passphrase)
        } catch let error as SecurityActionError {
            errorKey = error.messageKey
        } catch {
            errorKey = SecurityMessageKey.setupFailed
        }
        refreshStatus()
    }

    /// Web's "I understand — I've saved it": drops the code from memory.
    func acknowledgeRecoveryCode() {
        recoveryCode = nil
    }

    // MARK: - Unlock / lock

    func unlock(secret: String, useRecovery: Bool) async {
        errorKey = nil
        busy = true
        defer { busy = false }
        do {
            if useRecovery {
                try await securityRepository.unlockWithRecovery(code: secret)
            } else {
                try await securityRepository.unlock(passphrase: secret)
            }
        } catch let error as SecurityActionError {
            errorKey = error.messageKey
        } catch {
            // Web collapses every unlock failure into one message per mode, and
            // so does this: the useful distinction is "the thing you typed is
            // wrong", not which layer noticed.
            errorKey = useRecovery ? SecurityMessageKey.invalidRecovery : SecurityMessageKey.wrongPassphrase
        }
        refreshStatus()
    }

    func lock() {
        securityRepository.lockSession()
        grants = []
        grantIssued = nil
        grantErrorKey = nil
        refreshStatus()
    }

    /// Clearing the field also clears the error, as retyping does on web.
    func clearError() {
        errorKey = nil
    }

    // MARK: - Support grants

    func issueGrant(scope: String) async {
        busy = true
        grantIssued = nil
        grantErrorKey = nil
        defer { busy = false }
        do {
            let issued = try await securityRepository.issueSupportGrant(scope: scope)
            grantIssued = GrantIssuedNotice(scope: scope, expiresAtIso: issued.expiresAtIso)
            grants = (try? await securityRepository.activeGrants()) ?? grants
        } catch let error as SecurityActionError {
            grantErrorKey = error.messageKey
        } catch {
            grantErrorKey = SecurityMessageKey.grantFailed
        }
    }

    func revokeGrant(id: String) async {
        try? await securityRepository.revokeGrant(grantId: id)
        grants = (try? await securityRepository.activeGrants()) ?? []
    }
}

/// Web's `setInterval(refresh, 30_000)`.
private let grantPollNanos: UInt64 = 30_000_000_000
