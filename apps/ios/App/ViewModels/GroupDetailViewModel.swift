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
    /// Kept alongside the formatted string so the summary can total the group.
    public let amountMinor: Int64
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
    @ObservationIgnored
    @Injected(\.invitesRepository) private var invitesRepository

    public var group: SplitGroup?

    /// The group's headline figures — total spent, what you are owed, what you
    /// owe — in the group's own currency.
    ///
    /// Web's summary card. Without it the screen listed rows and left the user
    /// to add them up: you could not tell what a trip cost in total, or which
    /// way your own side of it leaned, without doing arithmetic by hand.
    public var summary: GroupSummaryUiModel? {
        guard let g = group else { return nil }
        return GroupSummaryUiModel(
            totalSpentFormatted: formatMoney(expenses.reduce(Int64(0)) { $0 + $1.amountMinor }, g.currency),
            owedFormatted: formatMoney(members.reduce(Int64(0)) { $0 + max(0, $1.net) }, g.currency),
            oweFormatted: formatMoney(members.reduce(Int64(0)) { $0 + max(0, -$1.net) }, g.currency),
            memberCount: members.count,
            startDate: g.startDate,
            endDate: g.endDate,
            autoSplit: g.autoSplit
        )
    }
    public var members: [MemberUiModel] = []
    public var expenses: [ExpenseUiModel] = []
    public var settlements: [SettlementUiModel] = []
    public var accounts: [AccountOption] = []
    public var loaded = false
    public var errorMessage: String?
    public var upiStage: UpiStage = .idle

    // MARK: - invites

    /// Everyone this user is connected to, as the invite box's candidates.
    public var connections: [Invitee] = []
    public var selected: [Invitee] = []
    public var inviteQuery = ""
    public var inviting = false
    /// The last run's counts, for the summary line. Nil before the first.
    public var inviteOutcome: InviteOutcome?
    /// A share link, once one has been created.
    public var inviteLink: String?
    /// A failure worth showing, already worded by the repository.
    public var inviteError: String?

    /// What the box should offer right now. Computed by Domain, not here.
    public var suggestions: InviteSuggestions {
        inviteSuggestions(
            connections: connections,
            memberIds: members.map(\.userId),
            selected: selected,
            query: inviteQuery
        )
    }

    public func addInvitee(_ invitee: Invitee) {
        selected.append(invitee)
        inviteQuery = ""
    }

    public func removeInvitee(key: String) {
        selected.removeAll { inviteeKey($0) == key }
    }

    /// Web resets the whole panel every time the modal opens.
    public func resetInvite() {
        selected = []
        inviteQuery = ""
        inviteOutcome = nil
        inviteLink = nil
        inviteError = nil
    }

    /**
     Invite everyone in the chips.

     One call per invitee, as web does — the Edge Function takes a single
     address, and batching would need a server change. A failure is counted and
     the loop continues: inviting four people and having one address bounce
     should still add the other three.
     */
    public func inviteSelected() {
        let picked = selected
        guard !picked.isEmpty, !inviting else { return }
        inviting = true
        inviteOutcome = nil
        inviteLink = nil
        inviteError = nil
        Task { [weak self] in
            guard let self else { return }
            var added = 0
            var links = 0
            var failed: [String] = []
            for invitee in picked {
                do {
                    let result = try await self.invitesRepository.createInvite(
                        groupId: self.groupId,
                        email: invitee.email.isEmpty ? nil : invitee.email
                    )
                    if result.added { added += 1 } else { links += 1 }
                } catch {
                    failed.append(inviteeLabel(invitee))
                }
            }
            self.selected = []
            self.inviteQuery = ""
            self.inviting = false
            self.inviteOutcome = InviteOutcome(added: added, links: links, failed: failed)
        }
    }

    /// A share link with no particular recipient. Web's `shareLink()`.
    public func createShareLink() {
        guard !inviting else { return }
        inviting = true
        inviteOutcome = nil
        inviteLink = nil
        inviteError = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.invitesRepository.createInvite(groupId: self.groupId)
                self.inviteLink = result.link
            } catch let error as InviteError {
                self.inviteError = error.message
            } catch {
                self.inviteError = error.localizedDescription
            }
            self.inviting = false
        }
    }

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
        // The invite box's candidates. A connection with no email cannot be
        // invited by this route; Domain drops those rather than the query, so
        // the empty string travels and the rule stays in one place.
        connections = conns.map { Invitee(id: $0.id, name: $0.name, email: $0.email ?? "") }
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
                        ExpenseUiModel(
                            id: e.id,
                            description: (e.description?.isEmpty == false) ? e.description! : S.Groups.expenseFallback,
                            amountFormatted: formatMoney(e.amount, e.currency),
                            amountMinor: e.amount,
                            date: String(e.occurredAt.prefix(10))
                        )
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
        // `fromMajor`, not `* 100`: the group carries its own currency, and a
        // zero-decimal one would be recorded a hundred times too large.
        let amountMinor = fromMajor(amountMajor, g.currency).amount
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

    /// Rename, re-date, or toggle auto-split. Matches web's `saveEdit()`.
    public func updateGroup(name: String, startDate: String, endDate: String, autoSplit: Bool) async -> String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a name." }
        do {
            try await splitsRepository.updateGroup(
                groupId: groupId, name: name, startDate: startDate, endDate: endDate, autoSplit: autoSplit
            )
            group = try await splitsRepository.getGroup(groupId: groupId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Soft-delete the group. Its expenses stay in the ledger — see the repo.
    public func deleteGroup() async -> String? {
        do {
            try await splitsRepository.deleteGroup(groupId: groupId)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Manual "mark settled" -- no UPI, matches web's confirmSettle("confirmed").
    public func settleManually(otherUserId: String, amountMajorText: String, direction: String, accountId: String?) async -> String? {
        guard let uid = userId, let g = group else { return "Couldn't determine the current user." }
        guard let amountMajor = Double(amountMajorText.replacingOccurrences(of: ",", with: "")), amountMajor > 0 else { return "Enter a valid amount." }
        do {
            _ = try await splitsRepository.settleUp(userId: uid, otherUserId: otherUserId, groupId: groupId, amount: fromMajor(amountMajor, g.currency).amount, direction: direction, accountId: accountId, currency: g.currency)
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
                amount: fromMajor(amountMajor, g.currency).amount, direction: direction, accountId: nil,
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

/// Web's summary card, as one value.
public struct GroupSummaryUiModel: Equatable {
    public let totalSpentFormatted: String
    public let owedFormatted: String
    public let oweFormatted: String
    public let memberCount: Int
    public let startDate: String?
    public let endDate: String?
    public let autoSplit: Bool
}
