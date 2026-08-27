import Foundation
import Observation
import Factory
import Domain
import Data
import PowerSync

/// Whether the first-run walkthrough is showing, and the two flags that close it.
///
/// A port of `apps/web/src/onboarding/useWalkthrough.ts`, including its split
/// storage: **done is permanent, skipped is for this launch only.** Web uses
/// `localStorage` for one and `sessionStorage` for the other, and the reason is
/// in the file: skipping is "not now", and someone who taps it while still
/// having no account should meet the walkthrough again next visit. There is no
/// `sessionStorage` on iOS, so `skipped` is held in memory on this object —
/// which is exactly the same lifetime, since the object dies with the process.
///
/// The decision itself is NOT here. It is `shouldShowWalkthrough()` in Domain,
/// vector-pinned across all 96 combinations of its six inputs, because the
/// guards exist to stop the dialog appearing at the wrong moment and "did not
/// appear" is the failure nobody notices until a returning user is told to set
/// their accounts up from scratch.
@MainActor
@Observable
public final class WalkthroughGate {
    @ObservationIgnored @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository
    @ObservationIgnored @Injected(\.powerSyncDatabase) private var db

    /// Matches web's `sanvya:walkthroughDone` localStorage key exactly, so the
    /// two clients mean the same thing by it even though the stores differ.
    private static let doneKey = "sanvya:walkthroughDone"

    private let defaults: UserDefaults

    /// Read synchronously in `init` so a returning user never gets one frame of
    /// the dialog. Web's comment records that the checklist this replaced had
    /// precisely that bug.
    private var done: Bool
    private var skipped = false
    private var syncPending = true
    private var accountCountLoaded = false
    private var realAccountCount = 0
    private var signedIn = false

    public var isOpen: Bool {
        shouldShowWalkthrough(
            done: done,
            skipped: skipped,
            syncPending: syncPending,
            accountCountLoaded: accountCountLoaded,
            realAccountCount: realAccountCount,
            signedIn: signedIn
        )
    }

    private var tasks: [Task<Void, Never>] = []

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.done = defaults.bool(forKey: Self.doneKey)
    }

    /// Idempotent — safe from every `.onAppear`.
    public func start() {
        guard tasks.isEmpty else { return }

        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await count in try self.ledgerRepository.watchRealAccountCount() {
                    self.realAccountCount = count
                    self.accountCountLoaded = true
                }
            } catch {
                // Unreadable: leave `accountCountLoaded` false. A count we
                // could not take is not a count of zero, and guessing zero
                // shows the walkthrough to someone who has accounts.
            }
        })

        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await state in self.authRepository.authState {
                // A guest has a session, so `signedInOffline` counts: web's
                // gate is `!!session`, not "signed in with an email".
                self.signedIn = state != .signedOut
            }
        })

        // `hasSynced` has no change stream on either SDK, so this polls the
        // same status object the diagnostics panel reads. It settles once and
        // then never changes for the life of the process, so the loop exits
        // for good the moment it flips — this is not a background poller.
        tasks.append(Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.db.currentStatus.hasSynced == true {
                    self.syncPending = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(400))
            }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Close for this launch only; it returns next time while there is still no
    /// account.
    public func skip() { skipped = true }

    /// Close for good.
    public func finish() {
        defaults.set(true, forKey: Self.doneKey)
        done = true
    }
}

/// The seven steps' own state: the two forms, and the two writes behind them.
///
/// Split from ``WalkthroughGate`` on purpose — the gate outlives the dialog and
/// is cheap; this holds a half-typed account name and dies with the sheet.
@MainActor
@Observable
public final class WalkthroughViewModel {
    @ObservationIgnored @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored @Injected(\.authRepository) private var authRepository
    @ObservationIgnored @Injected(\.prefsRepository) private var prefsRepository

    public var step = 1
    public var busy = false
    public var error: String?

    // Step 2 — account
    public var accountName = ""
    public var accountBalance = ""
    private var accountId: String?

    // Step 3 — first spend
    public var spendWhat = ""
    public var spendAmount = ""

    public private(set) var isGuest = false
    public private(set) var onTrial = false

    /// Trimmed, because a name of three spaces is not a name. Web guards the
    /// same way inside `saveAccount`; doing it here as well means the button is
    /// visibly disabled rather than silently doing nothing when tapped.
    public var canSaveAccount: Bool { !accountName.trimmed.isEmpty }

    public var canSaveSpend: Bool {
        !spendWhat.trimmed.isEmpty && (Double(spendAmount.trimmed) ?? 0) > 0
    }

    private var tasks: [Task<Void, Never>] = []

    public init() {}

    public func start() {
        guard tasks.isEmpty else { return }

        tasks.append(Task { [weak self] in
            guard let self else { return }
            self.isGuest = await self.authRepository.isGuest()
        })

        // Step 7 says one of two different things, and only one of them has a
        // countdown: `isTrial`, not `isPaid`. A paying subscriber is not on
        // trial and must not be told their trial is running.
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in try self.prefsRepository.watchEntitlement() {
                    self.onTrial = entitlementState(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        nowMillis: Int64((Date().timeIntervalSince1970 * 1000).rounded())
                    ).isTrial
                }
            } catch {
                // Offline: step 7 falls back to the plain plan copy, which is
                // true for everyone.
            }
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Create the first account from two fields.
    ///
    /// Everything else takes a sane default, so a nervous first-timer never
    /// meets the type / currency / overdraft form — all of it is editable later
    /// from the account's own edit screen. Web makes exactly these choices:
    /// `savings`, the base currency, `allow_negative: false`, and a colour
    /// derived from the name.
    public func saveAccount() {
        let name = accountName.trimmed
        guard !name.isEmpty, !busy else { return }
        busy = true
        error = nil
        let balanceText = accountBalance.trimmed
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                guard let userId = await self.resolveUserId() else { return }
                let base = baseCurrencyNow()
                let id = try await self.ledgerRepository.createAccount(
                    userId: userId,
                    name: name,
                    type: "savings",
                    currency: base,
                    icon: nil,
                    color: FormOptions.colorForId(name),
                    allowNegative: false
                )
                self.accountId = id
                // Only a positive opening balance is written. Web checks
                // `Number.isFinite(major) && major > 0` for the same reason:
                // "0" and "" are the same statement — "I have not told you" —
                // and an explicit zero opening balance is a real ledger row
                // that would have to be found and deleted later.
                if let major = Double(balanceText), major.isFinite, major > 0 {
                    try await self.ledgerRepository.setOpeningBalance(
                        userId: userId,
                        accountId: id,
                        balance: fromMajor(major, base),
                        occurredAt: nowIso()
                    )
                }
                self.step = 3
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Record the first spend against the account we just made.
    ///
    /// Web computes the minor amount as `Math.round(Number(amount) * 100)` —
    /// the hardcoded ×100 the rest of this port has been removing, and wrong
    /// for every currency that is not two-decimal: a first spend of ¥500 lands
    /// as ¥5. `fromMajor` uses the currency's own minor-unit count. Recorded in
    /// docs/mobile/PARITY_AUDIT.md under "Web bugs found while porting".
    public func saveSpend() {
        let desc = spendWhat.trimmed
        guard !desc.isEmpty, !busy else { return }
        let major = Double(spendAmount.trimmed) ?? 0
        guard major > 0 else { return }
        busy = true
        error = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false }
            do {
                guard let userId = await self.resolveUserId() else { return }
                // The account may not exist: step 2 offers "I'll do this
                // later". Web falls back to the first account it can find and,
                // failing that, moves on without recording anything rather
                // than showing an error for a step it told them was optional.
                var found = self.accountId
                if found == nil { found = try await self.ledgerRepository.firstRealAccountId() }
                guard let target = found else { self.step = 4; return }
                _ = try await self.ledgerRepository.createTransaction(
                    userId: userId,
                    accountId: target,
                    type: "expense",
                    amount: fromMajor(major, baseCurrencyNow()),
                    occurredAt: nowIso(),
                    labels: [],
                    description: desc
                )
                self.step = 4
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
