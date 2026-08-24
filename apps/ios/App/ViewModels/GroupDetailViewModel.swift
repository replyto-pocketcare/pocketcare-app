import Foundation
import Observation
import Factory
import Domain
import Data
import Supabase

public struct MemberUiModel: Identifiable, Equatable {
    public let userId: String
    public var id: String { userId }
    public let name: String
    public let net: Int64
    public let isSelf: Bool
}
public struct ExpenseUiModel: Identifiable, Equatable {
    public let id: String
    public let description: String
    public let amountFormatted: String
    public let date: String
}
public struct SettlementUiModel: Identifiable, Equatable {
    public let id: String
    public let fromUser: String
    public let toUser: String
    public let fromName: String
    public let toName: String
    public let amountFormatted: String
    public let date: String
}
public struct AccountOption: Identifiable, Equatable {
    public let id: String
    public let name: String
}

/// Payer-side UPI settle-up state machine -- mirrors PayViaUpi.tsx's Stage
/// type exactly (idle/fetching/ready/error), since there is no success
/// callback from a UPI Intent hand-off.
public enum UpiStage: Equatable {
    case idle
    case fetching
    case ready(vpa: String, displayName: String?)
    case error(message: String, code: String?)
}

/// Real port of apps/web/app/groups/[id]/page.tsx (task #30). See
/// docs/mobile/screen-specs/splits.md for the deliberate scope cut
/// (equal-split "Add expense" only; invite/itemized deferred).
///
/// Instantiated once per GroupDetailView via `@State`; [select] is called
/// from `.task(id: groupId)` and is safe to call again (cancels the
/// previous watch Tasks first) -- matching Android's GroupDetailViewModel
/// `select()` convention.
@Observable
@MainActor
public final class GroupDetailViewModel {
    @ObservationIgnored
    @Injected(\.splitsRepository) private var splitsRepository
    @ObservationIgnored
    @Injected(\.ledgerRepository) private var ledgerRepository
    @ObservationIgnored
    @Injected(\.upiRepository) private var upiRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository

    public var group: SplitGroup?
    public var members: [MemberUiModel] = []
    public var expenses: [ExpenseUiModel] = []
    public var settlements: [SettlementUiModel] = []
    public var accounts: [AccountOption] = []
    public var loaded = false
    public var errorMessage: String?
    public var upiStage: UpiStage = .idle

    private var groupId: String = ""
    private var userId: String?
    private var namesById: [String: String] = [:]
    private var tasks: [Task<Void, Never>] = []

    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

    public func select(_ groupId: String) async {
        if self.groupId == groupId, !tasks.isEmpty { return }
        cancel()
        self.groupId = groupId
        loaded = false

        let uid = await resolveUserId()
        self.userId = uid

        self.group = try? await splitsRepository.getGroup(groupId: groupId)
        let conns = (try? await firstConnections(uid)) ?? []
        namesById = Dictionary(uniqueKeysWithValues: conns.map { ($0.id, $0.name) })
        if let uid { namesById[uid] = S.Receipts.splitYou }
        loaded = true

        if let uid {
            tasks.append(Task {
                do {
                    let ids = try splitsRepository.watchGroupMemberIds(groupId: groupId)
                    for try await memberIds in ids {
                        await self.recomputeMembers(memberIds: memberIds, uid: uid)
                    }
                } catch { self.errorMessage = error.localizedDescription }
            })
        }

        tasks.append(Task {
            do {
                for try await list in try self.splitsRepository.watchGroupExpenses(groupId: groupId) {
                    self.expenses = list.map { e in
                        ExpenseUiModel(id: e.id, description: (e.description?.isEmpty == false) ? e.description! : S.Groups.expenseFallback, amountFormatted: formatMoney(e.amount, e.currency), date: String(e.occurredAt.prefix(10)))
                    }
                }
            } catch { self.errorMessage = error.localizedDescription }
        })

        tasks.append(Task {
            do {
                for try await list in try self.splitsRepository.watchGroupSettlements(groupId: groupId) {
                    self.settlements = list.map { s in
                        SettlementUiModel(
                            id: s.id, fromUser: s.fromUser, toUser: s.toUser,
                            fromName: s.fromUser == uid ? S.Receipts.splitYou : self.nameOf(s.fromUser),
                            toName: s.toUser == uid ? S.Receipts.splitYou : self.nameOf(s.toUser),
                            amountFormatted: formatMoney(s.amount, s.currency ?? baseCurrencyNow()), date: String(s.at.prefix(10))
                        )
                    }
                }
            } catch { self.errorMessage = error.localizedDescription }
        })

        tasks.append(Task {
            do {
                for try await list in try self.ledgerRepository.watchAccounts() {
                    self.accounts = list.filter { $0.type != "stocks" && $0.type != "mutual_funds" }.map { AccountOption(id: $0.id, name: $0.name) }
                }
            } catch { self.errorMessage = error.localizedDescription }
        })
    }

    /// One-shot: breaks out of the stream after its first emission (used
    /// only to seed [namesById] before the reactive member/expense/
    /// settlement Tasks start below). Matches Android's `.first()` on the
    /// equivalent Flow -- worst case if the underlying watch subscription
    /// isn't torn down promptly on early exit is a harmless extra
    /// subscription, not incorrect data.
    private func firstConnections(_ uid: String?) async throws -> [UserProfile] {
        guard let uid else { return [] }
        let stream = try splitsRepository.watchConnections(userId: uid)
        for try await value in stream { return value }
        return []
    }

    private func recomputeMembers(memberIds: [String], uid: String) async {
        let balances = (try? await splitsRepository.groupBalances(groupId: groupId, userId: uid)) ?? []
        var byId: [String: Int64] = [:]
        for b in balances { byId[b.userId] = b.net }
        var everyone = memberIds
        if !everyone.contains(uid) { everyone.append(uid) }
        var seen = Set<String>()
        everyone = everyone.filter { seen.insert($0).inserted }
        self.members = everyone.map { id in
            MemberUiModel(userId: id, name: id == uid ? S.Receipts.splitYou : nameOf(id), net: byId[id] ?? 0, isSelf: id == uid)
        }
    }

    private func nameOf(_ id: String) -> String { namesById[id] ?? S.Groups.someone }

    /// Equal-split add-expense -- see docs/mobile/screen-specs/splits.md's
    /// scope note: web's richer percent/exact/itemized modes are deferred
    /// to the receipt-scan work, this covers the common case end-to-end.
    public func addExpense(description: String, amountMajorText: String, payerId: String, payerAccountId: String?, participantIds: [String]) async -> String? {
        guard let uid = userId, let g = group else { return "Couldn't determine the current user." }
        guard let amountMajor = Double(amountMajorText.replacingOccurrences(of: ",", with: "")), amountMajor > 0, !participantIds.isEmpty else {
            return "Enter a valid amount and at least one participant."
        }
        let amountMinor = Int64((amountMajor * 100).rounded())
        do {
            _ = try await splitsRepository.createSplitExpense(
                userId: uid,
                input: SplitExpenseInput(
                    groupId: groupId, mode: "equal", total: money(amountMinor, g.currency),
                    participants: participantIds.map { ParticipantInput(userId: $0) },
                    payers: [PayerInput(userId: payerId, paid: amountMinor, accountId: payerAccountId)],
                    description: description.isEmpty ? nil : description,
                    occurredAt: ISO8601DateFormatter().string(from: Date())
                )
            )
            return nil
        } catch {
            return "Couldn't add the expense: \(error.localizedDescription)"
        }
    }

    /// Manual "mark settled" -- no UPI, matches web's confirmSettle("confirmed").
    public func settleManually(otherUserId: String, amountMajorText: String, direction: String, accountId: String?) async -> String? {
        guard let uid = userId, let g = group else { return "Couldn't determine the current user." }
        guard let amountMajor = Double(amountMajorText.replacingOccurrences(of: ",", with: "")), amountMajor > 0 else { return "Enter a valid amount." }
        do {
            _ = try await splitsRepository.settleUp(userId: uid, otherUserId: otherUserId, groupId: groupId, amount: Int64((amountMajor * 100).rounded()), direction: direction, accountId: accountId, currency: g.currency)
            return nil
        } catch {
            return "Couldn't record the settlement: \(error.localizedDescription)"
        }
    }

    /// Payer-side UPI fetch -- mirrors PayViaUpi.tsx's start().
    public func startUpiFetch(otherUserId: String) {
        upiStage = .fetching
        Task {
            do {
                let handle = try await upiRepository.fetchCounterpartyHandle(counterpartyId: otherUserId)
                self.upiStage = .ready(vpa: handle.vpa, displayName: handle.displayName)
            } catch let e as UpiHandleError {
                self.upiStage = .error(message: e.message, code: e.code)
            } catch {
                self.upiStage = .error(message: error.localizedDescription, code: nil)
            }
        }
    }

    public func resetUpiStage() { upiStage = .idle }

    /// Records the UPI hand-off as a "pending" settlement -- only the
    /// payee can confirm it arrived.
    public func recordUpiSettlement(otherUserId: String, amountMajorText: String, direction: String, upiRef: String) async -> String? {
        guard let uid = userId, let g = group else { return "Couldn't determine the current user." }
        guard let amountMajor = Double(amountMajorText.replacingOccurrences(of: ",", with: "")), amountMajor > 0 else { return "Enter a valid amount." }
        do {
            _ = try await splitsRepository.settleUp(
                userId: uid, otherUserId: otherUserId, groupId: groupId,
                amount: Int64((amountMajor * 100).rounded()), direction: direction, accountId: nil,
                currency: g.currency, status: "pending", method: "upi_intent", upiRef: upiRef
            )
            return nil
        } catch {
            return "Couldn't record the settlement: \(error.localizedDescription)"
        }
    }

    public func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
