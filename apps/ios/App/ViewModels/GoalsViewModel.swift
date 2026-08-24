import Foundation
import Observation
import Factory
import Domain
import Data

/// Ported from apps/web/app/goals/page.tsx per
/// docs/mobile/screen-specs/goals.md. Was a broken placeholder before this
/// pass (2026-08-06, task #25): GoalUiModel.targetDate read a real-but-
/// unused DB column (`target_date` -- confirmed nowhere in the real Goals
/// UI, only in the AI assistant's tool schema), no create/update/delete/
/// allocate existed, and it observed allocations per-goal with a
/// `.firstOrNull()`-shaped one-time read inside a `for try await` loop
/// that never actually re-fired. Also dropped a `CashflowUiModel`/
/// `cashflows` property that fed an invented "Goals & Cashflow" combined
/// tab in the old GoalsView.swift -- Planned Cashflow is a separate real
/// web feature/drawer item with no source read yet, out of scope here
/// (see the spec's header note; same class of drift as the removed
/// Dashboard "Recent Activity" section).
///
/// Fixed 2026-08-06 (list staleness bug): `goals` used to be populated by a
/// one-shot `reload()` called from `init()` and again from `.onAppear {
/// viewModel.start() }`. Add/Edit/Allocate Goal are `.sheet(...)`
/// presentations in GoalsView -- SwiftUI does not reliably fire
/// `.onDisappear`/`.onAppear` on the presenting view across a sheet's
/// presentation/dismissal, so `start()` (and its `reload()`) often never
/// ran again after the sheet closed, leaving a newly created/edited goal
/// invisible until the whole screen was torn down and recreated some other
/// way (e.g. navigating elsewhere and back). Now `goals`/`savingsAccounts`
/// are driven entirely by GoalsRepository.watchGoals()/watchAllocations()
/// (real db.watch(), same pattern as InvestmentsViewModel/LoansViewModel),
/// so any write from any screen/sheet shows up here immediately, with no
/// dependency on SwiftUI appear/disappear timing.
@Observable
@MainActor
public final class GoalsViewModel {
    @ObservationIgnored
    @Injected(\.goalsRepository) private var goalsRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public struct GoalUiModel: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let savedFormatted: String
        public let targetFormatted: String
        public let progress: Double // 0...1
        public let funded: Bool
        public let isEmergencyFund: Bool
        public let locked: Bool
        public let remainingMinor: Int64
        // Edit-form prefill -- raw, unformatted.
        public let rawName: String
        public let targetMajor: String
        public let currency: String
        public let alertTimeLocal: String
    }

    public struct SavingsAccountOption: Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
    }

    public var goals: [GoalUiModel] = []
    public var savingsAccounts: [SavingsAccountOption] = []
    public var hasEmergencyFund: Bool { goals.contains(where: \.isEmergencyFund) }

    private var goalsTask: Task<Void, Never>?
    private var allocsTask: Task<Void, Never>?
    private var accountsTask: Task<Void, Never>?
    private var latestGoals: [Goal] = []
    private var latestAllocs: [GoalAllocation] = []

    public init() {
        start()
    }

    /// Idempotent -- safe to call from every `.onAppear` even though the
    /// live subscriptions started here no longer need re-triggering to
    /// pick up writes (see the type doc comment). Guarded by `goalsTask`
    /// alone so all three tasks are always started/stopped together.
    public func start() {
        guard goalsTask == nil else { return }
        goalsTask = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            do {
                let stream = try await self.goalsRepository.watchGoals(userId: userId)
                for try await dbGoals in stream {
                    self.latestGoals = dbGoals
                    self.rebuildGoalsUi()
                }
            } catch {
                print("Failed to watch goals: \(error)")
            }
        }
        allocsTask = Task { [weak self] in
            guard let self else { return }
            guard let userId = await self.resolveUserId() else { return }
            do {
                let stream = try await self.goalsRepository.watchAllocations(userId: userId)
                for try await allocs in stream {
                    self.latestAllocs = allocs
                    self.rebuildGoalsUi()
                }
            } catch {
                print("Failed to watch goal allocations: \(error)")
            }
        }
        accountsTask = Task { [weak self] in
            guard let self else { return }
            guard let stream = try? self.ledgerRepository.watchAccounts(includeArchived: false) else { return }
            do {
                for try await rows in stream {
                    self.savingsAccounts = rows
                        .filter { $0.type == "savings" }
                        .map { SavingsAccountOption(id: $0.id, name: $0.name) }
                }
            } catch {
                print("Failed to watch savings accounts: \(error)")
            }
        }
    }

    public func cancel() {
        goalsTask?.cancel(); goalsTask = nil
        allocsTask?.cancel(); allocsTask = nil
        accountsTask?.cancel(); accountsTask = nil
    }

    /// Recomputes `goals` from the latest cached emissions of both live
    /// streams -- called whenever either one fires, so a change to just
    /// `goals` or just `goal_allocations` alone is reflected immediately.
    private func rebuildGoalsUi() {
        let dbGoals = latestGoals
        let allocs = latestAllocs
        func saved(_ goalId: String) -> Int64 {
            allocs.filter { $0.goalId == goalId }.reduce(0) { $0 + $1.amountBlocked }
        }
        let ef = dbGoals.first(where: \.isEmergencyFund)
        let efFunded = ef.map { saved($0.id) >= $0.targetAmount } ?? true

        goals = dbGoals.map { g in
            let savedAmount = saved(g.id)
            let pct = g.targetAmount > 0 ? min(1.0, Double(savedAmount) / Double(g.targetAmount)) : 0
            let funded = g.targetAmount > 0 && savedAmount >= g.targetAmount
            let remaining = max(0, g.targetAmount - savedAmount)
            return GoalUiModel(
                id: g.id,
                name: g.name,
                savedFormatted: compactMoney(savedAmount, g.currency),
                targetFormatted: compactMoney(g.targetAmount, g.currency),
                progress: pct,
                funded: funded,
                isEmergencyFund: g.isEmergencyFund,
                locked: !g.isEmergencyFund && !efFunded,
                remainingMinor: remaining,
                rawName: g.name,
                targetMajor: formatMajorPlain(g.targetAmount),
                currency: g.currency,
                alertTimeLocal: utcToLocalTime(g.alertTimeUtc)
            )
        }
    }

    /// Matches web's addGoal(): validation, priority = current goal count.
    public func create(name: String, targetMajorText: String, currency: String, isEmergencyFund: Bool, alertTimeLocal: String) async -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Enter a goal name." }
        guard let targetMajor = Double(targetMajorText), targetMajor > 0 else { return "Enter a target greater than 0." }
        guard let userId = await resolveUserId() else { return "Couldn't determine the current user." }
        do {
            try await goalsRepository.create(
                userId: userId,
                name: trimmedName,
                targetAmount: Int64((targetMajor * 100).rounded()),
                currency: currency,
                isEmergencyFund: isEmergencyFund && !hasEmergencyFund,
                priority: Int64(goals.count),
                alertTimeUtc: localToUtcTime(alertTimeLocal)
            )
            return nil
        } catch {
            return "Couldn't create the goal: \(error.localizedDescription)"
        }
    }

    /// Matches web's saveEdit(): name/target/alert-time only.
    public func update(id: String, name: String, targetMajorText: String, alertTimeLocal: String) async -> String? {
        do {
            let targetMajor = Double(targetMajorText) ?? 0
            try await goalsRepository.update(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                targetAmount: Int64((targetMajor * 100).rounded()),
                alertTimeUtc: localToUtcTime(alertTimeLocal)
            )
            return nil
        } catch {
            return "Couldn't save changes: \(error.localizedDescription)"
        }
    }

    /// Soft-deletes the goal only -- no cascade to its allocations, matching
    /// web (see GoalsRepository.swift's doc comment).
    public func delete(id: String) async {
        do {
            try await goalsRepository.delete(id: id)
        } catch {
            print("Failed to delete goal: \(error)")
        }
    }

    /// Matches web's allocate(): caps at the goal's remaining amount before
    /// inserting.
    public func allocate(goalId: String, sourceAccountId: String, amountMajorText: String, remainingMinor: Int64, currency: String) async -> String? {
        guard let amountMajor = Double(amountMajorText), amountMajor > 0 else { return "Enter an amount." }
        guard let userId = await resolveUserId() else { return "Couldn't determine the current user." }
        let requested = Int64((amountMajor * 100).rounded())
        let capped = min(requested, remainingMinor)
        guard capped > 0 else { return nil }
        do {
            try await goalsRepository.createAllocation(userId: userId, goalId: goalId, sourceAccountId: sourceAccountId, amountBlocked: capped)
            return nil
        } catch {
            return "Couldn't allocate funds: \(error.localizedDescription)"
        }
    }

    /// See AppDelegate.swift's `?? await` precedent -- `??`'s RHS is an
    /// `@autoclosure`, so `currentUserId ?? (try? await ensureUser())` is
    /// invalid Swift; use an explicit if/else instead.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

}

/// Locale-aware compact currency (e.g. ₹1.5L for INR, $1.2K otherwise) --
/// approximates web's `Intl.NumberFormat(..., { notation: "compact" })`
/// rather than reimplementing its exact breakpoints, per the spec's
/// "Deferred" note (acceptable drift, not pixel-critical).
// compactMoney moved to App/Components/MoneyFormat.swift — one copy, masked,
// with the divisor from minorUnits(currency) rather than a hardcoded 100.

// utcToLocalTime/localToUtcTime are NOT redeclared here -- they're already
// internal (module-default access, no `private`) top-level functions in
// BudgetsViewModel.swift, and both files are in the same App target, so
// they're directly callable with no import needed. Kotlin's per-package
// visibility (Android's equivalent duplication) doesn't have this
// same-module shortcut, which is why the Android port below still imports
// them explicitly instead.
