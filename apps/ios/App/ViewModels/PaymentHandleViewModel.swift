import Data
import Domain
import Factory
import Foundation
import Observation
import Supabase

/**
 "Your UPI ID" — the Settings section's state.

 Ports `apps/web/src/payments/PaymentHandlePanel.tsx`. Every call belongs to
 `UpiRepository`; what is here is web's four pieces of component state (the
 saved hint, the busy flag, the error and the expanded log) plus the one effect
 that loads the hint.

 Self-contained rather than fed from `SettingsViewModel`, matching
 `SecurityViewModel`: web's panel calls `useSession()` itself, and reading the
 session here keeps the section droppable into any screen the way web's is. The
 session read goes through `client.auth` for the same reason `SettingsViewModel`
 does — `AuthRepository` exposes `currentUserId` and `isGuest()` but not the
 username, and the username is what a payer's UPI app shows.

 The error string is the SERVER's, verbatim, and deliberately not an i18n key.
 Every message this can surface comes from the `payment-handle` Edge Function
 ("Create an account before saving a UPI ID.", "Couldn't save that: …"), and web
 renders `e.message` for exactly the same reason. Translating them would mean
 maintaining a native copy of the function's error vocabulary that goes stale
 silently. The strings the SECTION owns are all catalogued.

 Mirrors Android's PaymentHandleViewModel.kt.
 */
@Observable
@MainActor
final class PaymentHandleViewModel {

    @ObservationIgnored
    @Injected(\.upiRepository) private var upiRepository
    @ObservationIgnored
    @Injected(\.supabaseClient) private var client

    /**
     True until BOTH the session and the saved hint are known.

     Web's panel starts `loading = true` and its `useSession()` hydrates from a
     localStorage cache, so it effectively never renders the guest message at
     someone who is signed in. Native has no such cache, so the session read is
     folded into the same loading flag — otherwise every open of Settings would
     flash "Create an account to add a UPI ID" at an account holder, which is
     the same lie as flashing the empty form at someone who already saved a
     handle (web's own comment on that effect).
     */
    private(set) var loading = true

    /// Web's `useCanSavePaymentHandle()` — signed in, and not a guest.
    private(set) var canSave = false

    /// The masked hint for the saved handle, or nil when there isn't one.
    private(set) var hint: String?

    private(set) var busy = false
    private(set) var error: String?

    /// Who has fetched your UPI ID. Synced, so it reads from local SQLite and
    /// works offline — see `UpiRepository.watchDisclosures()`.
    private(set) var disclosures: [HandleDisclosure] = []

    /// The display name sent with a save, so the payer's UPI app has something
    /// to show. Web passes `session?.username`.
    @ObservationIgnored
    private var username = ""

    @ObservationIgnored
    private var loaded = false
    @ObservationIgnored
    private var disclosureTask: Task<Void, Never>?

    /**
     Web's `useEffect(…, [canSave])`, plus the disclosure subscription.

     The hint load is guarded so returning to Settings does not refetch: it is a
     masked string that only changes when this section itself changes it. The
     stream is guarded on its own task handle instead, the same way
     `RecurringViewModel` does — a live `db.watch()` should outlive one
     appearance of the view, not be torn down and stood back up on every one.
     */
    func start() async {
        await loadOnce()
        guard disclosureTask == nil else { return }
        disclosureTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in try self.upiRepository.watchDisclosures() {
                    self.disclosures = rows
                }
            } catch {}
        }
    }

    private func loadOnce() async {
        guard !loaded else { return }
        loaded = true

        // Bound in two steps, exactly as `SettingsViewModel.loadSession()` does
        // it: `client.auth.session` is an async throwing property, and chaining
        // `.user` off a `try? await` of it is the kind of thing the compiler
        // blames on the wrong expression.
        guard let session = try? await client.auth.session else {
            canSave = false
            loading = false
            return
        }
        let user = session.user
        username = user.userMetadata["username"]?.stringValue ?? ""
        let allowed = !user.isAnonymous
        canSave = allowed
        guard allowed else {
            loading = false
            return
        }
        // The repository already degrades to the cached hint on a failed read,
        // so there is nothing to catch and nothing worth an error banner over a
        // field the user has not touched yet.
        hint = await upiRepository.getMyPaymentHandle()
        loading = false
    }

    /// Web's `save()`. `normalizedVpa` is already trimmed and lower-cased.
    ///
    /// Returns true when the handle was stored, so the view can clear its input
    /// — web does that with `setValue("")` inside the same `try`. The field
    /// stays in the view rather than moving up here: the section is otherwise
    /// stateless, and a bound `String` in an `@Observable` model would fight
    /// SwiftUI's own `@State` on the text field.
    @discardableResult
    func save(normalizedVpa: String) async -> Bool {
        if busy { return false }
        busy = true
        error = nil
        defer { busy = false }
        do {
            hint = try await upiRepository.savePaymentHandle(vpa: normalizedVpa, displayName: username)
            return true
        } catch let handleError as UpiHandleError {
            error = handleError.message
            return false
        } catch {
            // `self.` is load-bearing: the catch binding is also called `error`
            // and shadows the property.
            self.error = error.localizedDescription
            return false
        }
    }

    /// Web's `forget()`.
    func forget() async {
        if busy { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await upiRepository.forgetPaymentHandle()
            hint = nil
        } catch let handleError as UpiHandleError {
            error = handleError.message
        } catch {
            // `self.` is load-bearing here too -- see save(normalizedVpa:).
            self.error = error.localizedDescription
        }
    }

    /// The watch is a long-lived stream; without this it outlives the panel
    /// and keeps a strong `self` for the life of the process. Android's side
    /// is scoped by `WhileSubscribed(5000)` and needs no equivalent.
    deinit { disclosureTask?.cancel() }
}
