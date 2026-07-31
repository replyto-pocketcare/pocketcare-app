import Foundation
import PowerSync
import Domain

// Read/write facade for shared expenses between people/groups (P2.5):
// split_groups, split_group_members, expenses, expense_participants,
// settlements, connections. Mirrors apps/web/src/splits/write.ts and
// apps/web/src/splits/hooks.ts exactly -- there is NO dedicated repository
// class for this domain in packages/data (confirmed by reading both files
// there in full); the web app instead builds directly on the generic
// insertRow/updateRow helpers plus raw useQuery SQL, so THIS file's
// query/write shapes are the actual spec (CLAUDE.md golden rule 8), not a
// design of convenience. Mirrors
// apps/android/data/.../repository/SplitsRepository.kt.
//
// Balance math is never recomputed here: every derived balance goes through
// the already-ported pairwiseEdges (P1.4b) and the splitsinsights functions
// (also P1.4b), exactly mirroring hooks.ts's own computeBalances()/
// useFriendInsights().
//
// Deliberately OUT of scope for this pass (documented, not an oversight):
// - The itemized-bill write path (apps/web/src/splits/writeItemized.ts --
//   expense_items/expense_item_shares, receipt-scan-driven). Balances are
//   fully correct without it (expense_participants is the single source of
//   truth per hooks.ts's own comment); itemized breakdown is purely
//   explanatory UI.
// - createInvite/acceptInvite -- Supabase Edge Function HTTP calls, not the
//   local PowerSync DB; belongs with P2.4 (auth) or a future networking layer.
//
// REACTIVITY NOTE (same asymmetry as LedgerRepository.swift, extended here):
// single-table reads (groups/groupMembers/groupExpenses/groupSettlements/
// connections) are real AsyncThrowingStream watches. ALL derived/composed
// balance views (friendBalances, groupBalances, splitOverview,
// friendInsights, personLedger) are one-shot async snapshots -- on BOTH
// platforms this time (the Kotlin mirror also made these one-shot, not just
// Swift), since combining 3-4 queries into one derived view would otherwise
// roughly triple this file's size for a Phase-2 Done-when that doesn't
// require live reactivity here.

public struct SplitGroup: Sendable {
    public let id: String
    public let createdBy: String
    public let name: String
    public let kind: String
    public let isDirect: Bool
    public let startDate: String?
    public let endDate: String?
    public let autoSplit: Bool
    public let defaultMode: String
    public let currency: String
}

public struct GroupExpense: Sendable {
    public let id: String
    public let description: String?
    public let amount: Int64
    public let currency: String
    public let occurredAt: String
    public let hasItems: Bool
}

/// Disputed settlements are already excluded at the query level -- matches
/// every settlements read in hooks.ts; missing that filter silently
/// corrupts a balance.
public struct GroupSettlement: Sendable {
    public let id: String
    public let fromUser: String
    public let toUser: String
    public let amount: Int64
    public let currency: String?
    public let at: String
    public let status: String?
}

public struct UserProfile: Sendable {
    public let id: String
    public let name: String
    public let email: String?
}

/// + = they owe you.
public struct FriendBalance: Sendable {
    public let userId: String
    public let net: Int64
}

public struct ParticipantInput: Sendable {
    public let userId: String
    public let value: Double?
    public init(userId: String, value: Double? = nil) {
        self.userId = userId
        self.value = value
    }
}

public struct PayerInput: Sendable {
    public let userId: String
    public let paid: Int64
    public let accountId: String?
    public init(userId: String, paid: Int64, accountId: String? = nil) {
        self.userId = userId
        self.paid = paid
        self.accountId = accountId
    }
}

/// [mode] is one of "equal" | "exact" | "percent" -- kept as a raw String
/// (not an enum) matching this port's established convention for DB `type`-
/// shaped columns elsewhere.
public struct SplitExpenseInput: Sendable {
    public let groupId: String
    public let mode: String
    public let total: Money
    public let participants: [ParticipantInput]
    public let payers: [PayerInput]
    public let categoryId: String?
    public let description: String?
    public let note: String?
    public let occurredAt: String
    public init(
        groupId: String, mode: String, total: Money, participants: [ParticipantInput], payers: [PayerInput],
        categoryId: String? = nil, description: String? = nil, note: String? = nil, occurredAt: String
    ) {
        self.groupId = groupId
        self.mode = mode
        self.total = total
        self.participants = participants
        self.payers = payers
        self.categoryId = categoryId
        self.description = description
        self.note = note
        self.occurredAt = occurredAt
    }
}

public struct PendingSettlement: Sendable {
    public let id: String
    public let fromUser: String
    public let toUser: String
    public let amount: Int64
    public let currency: String
    public let groupId: String
    public let status: String
    public let upiRef: String?
    public let createdAt: String
    public init(id: String, fromUser: String, toUser: String, amount: Int64, currency: String, groupId: String, status: String, upiRef: String?, createdAt: String) {
        self.id = id
        self.fromUser = fromUser
        self.toUser = toUser
        self.amount = amount
        self.currency = currency
        self.groupId = groupId
        self.status = status
        self.upiRef = upiRef
        self.createdAt = createdAt
    }
}

public struct GroupOverview: Sendable {
    public let group: SplitGroup
    /// Other members, excludes the caller, in join order.
    public let memberIds: [String]
    public let peopleCount: Int
    public let net: Int64
    public let perUser: [FriendBalance]
}

public struct SplitOverview: Sendable {
    public let netPosition: Int64
    public let owed: Int64
    public let owe: Int64
    public let groups: [GroupOverview]
    public let direct: [FriendBalance]
}

public struct PersonLine: Sendable {
    public let id: String
    public let kind: String
    public let description: String
    public let date: String
    public let net: Int64
}

private struct Part: Sendable { let expenseId: String; let groupId: String; let userId: String; let paidAmount: Int64; let shareAmount: Int64 }
private struct Sett: Sendable { let groupId: String; let fromUser: String; let toUser: String; let amount: Int64 }
private struct SettRow: Sendable { let id: String; let fromUser: String; let toUser: String; let amount: Int64; let at: String }

private func groupMapper(_ cursor: SqlCursor) throws -> SplitGroup {
    SplitGroup(
        id: try cursor.getString(name: "id"),
        createdBy: try cursor.getString(name: "created_by"),
        name: try cursor.getString(name: "name"),
        kind: try cursor.getString(name: "kind"),
        isDirect: (try cursor.getBooleanOptional(name: "is_direct")) ?? false,
        startDate: try cursor.getStringOptional(name: "start_date"),
        endDate: try cursor.getStringOptional(name: "end_date"),
        autoSplit: (try cursor.getBooleanOptional(name: "auto_split")) ?? false,
        defaultMode: try cursor.getString(name: "default_mode"),
        currency: try cursor.getString(name: "currency")
    )
}

private func expenseMapper(_ cursor: SqlCursor) throws -> GroupExpense {
    GroupExpense(
        id: try cursor.getString(name: "id"),
        description: try cursor.getStringOptional(name: "description"),
        amount: try cursor.getInt64(name: "amount"),
        currency: try cursor.getString(name: "currency"),
        occurredAt: try cursor.getString(name: "occurred_at"),
        hasItems: (try cursor.getBooleanOptional(name: "has_items")) ?? false
    )
}

private func settlementMapper(_ cursor: SqlCursor) throws -> GroupSettlement {
    GroupSettlement(
        id: try cursor.getString(name: "id"),
        fromUser: try cursor.getString(name: "from_user"),
        toUser: try cursor.getString(name: "to_user"),
        amount: try cursor.getInt64(name: "amount"),
        currency: try cursor.getStringOptional(name: "currency"),
        at: try cursor.getString(name: "at"),
        status: try cursor.getStringOptional(name: "status")
    )
}

/// Mirrors hooks.ts's computeBalances(): folds every expense's participants
/// through pairwiseEdges (per-expense, so multi-payer math stays correct),
/// then nets settlements on top. Every balance read in this file routes
/// through this one function, matching the TS source's own single-
/// implementation discipline.
private func computeBalances(_ parts: [Part], _ settlements: [Sett], _ me: String) -> [FriendBalance] {
    var byExpense: [String: [Party]] = [:]
    var order: [String] = []
    for p in parts {
        if byExpense[p.expenseId] == nil { order.append(p.expenseId) }
        byExpense[p.expenseId, default: []].append(Party(userId: p.userId, share: p.shareAmount, paid: p.paidAmount))
    }
    var net: [String: Int64] = [:]
    var netOrder: [String] = []
    for expenseId in order {
        for e in pairwiseEdges(byExpense[expenseId] ?? [], me) {
            if net[e.userId] == nil { netOrder.append(e.userId) }
            net[e.userId, default: 0] += e.amount
        }
    }
    for s in settlements {
        if s.toUser == me {
            if net[s.fromUser] == nil { netOrder.append(s.fromUser) }
            net[s.fromUser, default: 0] -= s.amount
        } else if s.fromUser == me {
            if net[s.toUser] == nil { netOrder.append(s.toUser) }
            net[s.toUser, default: 0] += s.amount
        }
    }
    return netOrder.map { FriendBalance(userId: $0, net: net[$0] ?? 0) }
}

private func computeShares(_ mode: String, _ total: Money, _ participants: [ParticipantInput]) -> [Int64] {
    switch mode {
    case "equal":
        return splitEqual(total.amount, participants.count)
    case "percent":
        return splitByWeights(total.amount, participants.map { $0.value ?? 0.0 })
    default:
        return participants.map { p in
            let v = (p.value ?? 0.0).rounded()
            return Int64(max(0.0, v))
        }
    }
}

public final class SplitsRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let ledger: LedgerRepository

    public init(db: PowerSyncDatabaseProtocol, ledger: LedgerRepository) {
        self.db = db
        self.ledger = ledger
    }

    // ---- reads (reactive, single table) ----

    public func watchGroups(includeDirect: Bool = false) throws -> AsyncThrowingStream<[SplitGroup], Error> {
        let extra = includeDirect ? "" : "AND IFNULL(is_direct,0)=0"
        return try db.watch(
            sql: """
                SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
                FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 \(extra) ORDER BY created_at DESC
                """,
            parameters: [],
            mapper: groupMapper
        )
    }

    public func watchGroupMemberIds(groupId: String) throws -> AsyncThrowingStream<[String], Error> {
        try db.watch(
            sql: "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL ORDER BY created_at",
            parameters: [groupId],
            mapper: { cursor in try cursor.getString(name: "user_id") }
        )
    }

    public func watchGroupExpenses(groupId: String) throws -> AsyncThrowingStream<[GroupExpense], Error> {
        try db.watch(
            sql: "SELECT id, description, amount, currency, occurred_at, has_items FROM expenses WHERE group_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC",
            parameters: [groupId],
            mapper: expenseMapper
        )
    }

    public func watchGroupSettlements(groupId: String) throws -> AsyncThrowingStream<[GroupSettlement], Error> {
        try db.watch(
            sql: """
                SELECT id, from_user, to_user, amount, currency, COALESCE(settled_at, created_at) AS at, status
                FROM settlements WHERE group_id = ? AND deleted_at IS NULL AND IFNULL(status,'confirmed') <> 'disputed' ORDER BY at DESC
                """,
            parameters: [groupId],
            mapper: settlementMapper
        )
    }

    /// Users connected to [userId] (accepted invites / shared groups).
    public func watchConnections(userId: String) throws -> AsyncThrowingStream<[UserProfile], Error> {
        try db.watch(
            sql: """
                SELECT p.id AS id, p.display_name AS display_name, p.email AS email
                FROM connections c JOIN profiles p ON p.id = (CASE WHEN c.user_a = ? THEN c.user_b ELSE c.user_a END)
                WHERE c.deleted_at IS NULL AND (c.user_a = ? OR c.user_b = ?)
                """,
            parameters: [userId, userId, userId],
            mapper: { cursor in
                let name = try cursor.getStringOptional(name: "display_name")
                let email = try cursor.getStringOptional(name: "email")
                let display = (name?.isEmpty == false) ? name! : (email?.split(separator: "@").first.map(String.init) ?? "Someone")
                return UserProfile(id: try cursor.getString(name: "id"), name: display, email: email)
            }
        )
    }

    // ---- reads (one-shot; see REACTIVITY NOTE above) ----

    /// Global per-user balances across all of [userId]'s groups.
    public func friendBalances(userId: String) async throws -> [FriendBalance] {
        let parts = try await db.getAll(
            sql: """
                SELECT expense_id, group_id, user_id, paid_amount, share_amount FROM expense_participants
                WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM expenses WHERE deleted_at IS NULL)
                """,
            parameters: []
        ) { cursor in
            Part(expenseId: try cursor.getString(name: "expense_id"), groupId: try cursor.getString(name: "group_id"), userId: try cursor.getString(name: "user_id"), paidAmount: try cursor.getInt64(name: "paid_amount"), shareAmount: try cursor.getInt64(name: "share_amount"))
        }
        let setts = try await db.getAll(
            sql: "SELECT group_id, from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            parameters: []
        ) { cursor in
            Sett(groupId: try cursor.getString(name: "group_id"), fromUser: try cursor.getString(name: "from_user"), toUser: try cursor.getString(name: "to_user"), amount: try cursor.getInt64(name: "amount"))
        }
        return computeBalances(parts, setts, userId)
    }

    /// Per-user balances within one group.
    public func groupBalances(groupId: String, userId: String) async throws -> [FriendBalance] {
        let parts = try await db.getAll(
            sql: "SELECT expense_id, group_id, user_id, paid_amount, share_amount FROM expense_participants WHERE group_id = ? AND deleted_at IS NULL",
            parameters: [groupId]
        ) { cursor in
            Part(expenseId: try cursor.getString(name: "expense_id"), groupId: try cursor.getString(name: "group_id"), userId: try cursor.getString(name: "user_id"), paidAmount: try cursor.getInt64(name: "paid_amount"), shareAmount: try cursor.getInt64(name: "share_amount"))
        }
        let setts = try await db.getAll(
            sql: "SELECT group_id, from_user, to_user, amount FROM settlements WHERE group_id = ? AND deleted_at IS NULL AND status <> 'disputed'",
            parameters: [groupId]
        ) { cursor in
            Sett(groupId: try cursor.getString(name: "group_id"), fromUser: try cursor.getString(name: "from_user"), toUser: try cursor.getString(name: "to_user"), amount: try cursor.getInt64(name: "amount"))
        }
        return computeBalances(parts, setts, userId)
    }

    /// Everything the Splits ledger needs, computed in one pass. Matches
    /// useSplitOverview() exactly, including folding direct (1:1) groups
    /// into aggregate per-person balances rather than listing them as groups.
    public func splitOverview(userId: String) async throws -> SplitOverview {
        let groups = try await db.getAll(
            sql: """
                SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
                FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 ORDER BY created_at DESC
                """,
            parameters: [],
            mapper: groupMapper
        )
        let members = try await db.getAll(
            sql: "SELECT group_id, user_id FROM split_group_members WHERE deleted_at IS NULL ORDER BY created_at",
            parameters: []
        ) { cursor in (try cursor.getString(name: "group_id"), try cursor.getString(name: "user_id")) }
        let parts = try await db.getAll(
            sql: "SELECT group_id, expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
            parameters: []
        ) { cursor in
            Part(expenseId: try cursor.getString(name: "expense_id"), groupId: try cursor.getString(name: "group_id"), userId: try cursor.getString(name: "user_id"), paidAmount: try cursor.getInt64(name: "paid_amount"), shareAmount: try cursor.getInt64(name: "share_amount"))
        }
        let setts = try await db.getAll(
            sql: "SELECT group_id, from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            parameters: []
        ) { cursor in
            Sett(groupId: try cursor.getString(name: "group_id"), fromUser: try cursor.getString(name: "from_user"), toUser: try cursor.getString(name: "to_user"), amount: try cursor.getInt64(name: "amount"))
        }

        var partsByGroup: [String: [Part]] = [:]
        for p in parts { partsByGroup[p.groupId, default: []].append(p) }
        var settsByGroup: [String: [Sett]] = [:]
        for s in setts { settsByGroup[s.groupId, default: []].append(s) }
        var membersByGroup: [String: [String]] = [:]
        for (groupId, uid) in members { membersByGroup[groupId, default: []].append(uid) }

        var groupViews: [GroupOverview] = []
        var direct: [String: Int64] = [:]
        var directOrder: [String] = []
        var owed: Int64 = 0
        var owe: Int64 = 0

        for g in groups {
            let perUser = computeBalances(partsByGroup[g.id] ?? [], settsByGroup[g.id] ?? [], userId)
            let net = perUser.reduce(Int64(0)) { $0 + $1.net }
            let allMembers = membersByGroup[g.id] ?? []
            let others = allMembers.filter { $0 != userId }
            owed += perUser.reduce(Int64(0)) { $0 + max(0, $1.net) }
            owe += perUser.reduce(Int64(0)) { $0 + max(0, -$1.net) }

            if g.isDirect {
                for b in perUser {
                    if direct[b.userId] == nil { directOrder.append(b.userId) }
                    direct[b.userId, default: 0] += b.net
                }
            } else {
                groupViews.append(GroupOverview(
                    group: g,
                    memberIds: others,
                    peopleCount: !allMembers.isEmpty ? allMembers.count : others.count + 1,
                    net: net,
                    perUser: perUser.filter { $0.net != 0 }
                ))
            }
        }

        let directList = directOrder.compactMap { userId2 -> FriendBalance? in
            guard let n = direct[userId2], n != 0 else { return nil }
            return FriendBalance(userId: userId2, net: n)
        }
        return SplitOverview(netPosition: owed - owe, owed: owed, owe: owe, groups: groupViews, direct: directList)
    }

    /// Per-friend rollup + headline insights across every group [userId] shares.
    /// Matches useFriendInsights() exactly: pairwise edges built here (the
    /// balance maths), behavioural analysis delegated to the already-ported
    /// splitsinsights domain (pure, P1.4b).
    public func friendInsights(userId: String) async throws -> (stats: [FriendStats], insights: [FriendInsight]) {
        let parts = try await db.getAll(
            sql: "SELECT group_id, expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
            parameters: []
        ) { cursor in
            Part(expenseId: try cursor.getString(name: "expense_id"), groupId: try cursor.getString(name: "group_id"), userId: try cursor.getString(name: "user_id"), paidAmount: try cursor.getInt64(name: "paid_amount"), shareAmount: try cursor.getInt64(name: "share_amount"))
        }
        let exps = try await db.getAll(
            sql: "SELECT id, occurred_at FROM expenses WHERE deleted_at IS NULL",
            parameters: []
        ) { cursor in (try cursor.getString(name: "id"), try cursor.getString(name: "occurred_at")) }
        let setts = try await db.getAll(
            sql: "SELECT from_user, to_user, amount, settled_at, created_at FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            parameters: []
        ) { cursor -> (String, String, Int64, String) in
            let at = (try cursor.getStringOptional(name: "settled_at")) ?? (try cursor.getString(name: "created_at"))
            return (try cursor.getString(name: "from_user"), try cursor.getString(name: "to_user"), try cursor.getInt64(name: "amount"), at)
        }

        var whenOf: [String: String] = [:]
        for (id, at) in exps { whenOf[id] = at }

        var byExpenseOrder: [String] = []
        var byExpenseGroup: [String: String] = [:]
        var byExpenseParties: [String: [Party]] = [:]
        var contributions: [String: [Contribution]] = [:]
        for p in parts {
            if byExpenseGroup[p.expenseId] == nil {
                byExpenseOrder.append(p.expenseId)
                byExpenseGroup[p.expenseId] = p.groupId
            }
            byExpenseParties[p.expenseId, default: []].append(Party(userId: p.userId, share: p.shareAmount, paid: p.paidAmount))
            if p.userId != userId {
                contributions[p.userId, default: []].append(Contribution(userId: p.userId, paid: p.paidAmount, share: p.shareAmount))
            }
        }

        var edges: [FriendEdge] = []
        for expenseId in byExpenseOrder {
            guard let at = whenOf[expenseId], let groupId = byExpenseGroup[expenseId] else { continue }
            let parties = byExpenseParties[expenseId] ?? []
            for e in pairwiseEdges(parties, userId) where e.amount != 0 {
                edges.append(FriendEdge(friendId: e.userId, groupId: groupId, at: at, amount: e.amount))
            }
        }

        var settlements: [FriendSettlement] = []
        for (fromUser, toUser, amount, at) in setts {
            if toUser == userId { settlements.append(FriendSettlement(friendId: fromUser, at: at, amount: amount)) }
            else if fromUser == userId { settlements.append(FriendSettlement(friendId: toUser, at: at, amount: -amount)) }
        }

        let stats = computeFriendStats(edges, settlements, contributions)
        return (stats, pickFriendInsights(stats))
    }

    /// The itemised ledger between [userId] and [otherId] across every group:
    /// each shared expense's pairwise edge plus settlements, newest first,
    /// with a running total. Matches usePersonLedger() exactly.
    public func personLedger(userId: String, otherId: String) async throws -> (lines: [PersonLine], total: Int64) {
        if otherId.isEmpty || userId.isEmpty { return ([], 0) }
        let parts = try await db.getAll(
            sql: "SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
            parameters: []
        ) { cursor -> (String, String, Int64, Int64) in
            (try cursor.getString(name: "expense_id"), try cursor.getString(name: "user_id"), try cursor.getInt64(name: "paid_amount"), try cursor.getInt64(name: "share_amount"))
        }
        let exps = try await db.getAll(
            sql: "SELECT id, description, occurred_at FROM expenses WHERE deleted_at IS NULL",
            parameters: []
        ) { cursor -> (String, String?, String) in
            (try cursor.getString(name: "id"), try cursor.getStringOptional(name: "description"), try cursor.getString(name: "occurred_at"))
        }
        let setts = try await db.getAll(
            sql: "SELECT id, from_user, to_user, amount, settled_at, created_at FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            parameters: []
        ) { cursor in
            SettRow(
                id: try cursor.getString(name: "id"),
                fromUser: try cursor.getString(name: "from_user"),
                toUser: try cursor.getString(name: "to_user"),
                amount: try cursor.getInt64(name: "amount"),
                at: (try cursor.getStringOptional(name: "settled_at")) ?? (try cursor.getString(name: "created_at"))
            )
        }

        var byExpenseOrder: [String] = []
        var byExpense: [String: [Party]] = [:]
        for (expenseId, uid, paid, share) in parts {
            if byExpense[expenseId] == nil { byExpenseOrder.append(expenseId) }
            byExpense[expenseId, default: []].append(Party(userId: uid, share: share, paid: paid))
        }
        var meta: [String: (String?, String)] = [:]
        for (id, description, occurredAt) in exps { meta[id] = (description, occurredAt) }

        var lines: [PersonLine] = []
        var total: Int64 = 0

        for expenseId in byExpenseOrder {
            let parties = byExpense[expenseId] ?? []
            let ids = parties.map(\.userId)
            guard ids.contains(userId), ids.contains(otherId) else { continue }
            guard let edge = pairwiseEdges(parties, userId).first(where: { $0.userId == otherId }), edge.amount != 0 else { continue }
            let m = meta[expenseId]
            let description = (m?.0?.isEmpty == false) ? m!.0! : "Expense"
            lines.append(PersonLine(id: expenseId, kind: "expense", description: description, date: m?.1 ?? "", net: edge.amount))
            total += edge.amount
        }
        for row in setts {
            let net: Int64
            if row.toUser == userId && row.fromUser == otherId { net = -row.amount }
            else if row.fromUser == userId && row.toUser == otherId { net = row.amount }
            else { continue }
            lines.append(PersonLine(id: row.id, kind: "settlement", description: net < 0 ? "They paid you back" : "You paid them back", date: row.at, net: net))
            total += net
        }

        let sorted = lines.sorted { $0.date > $1.date }
        return (sorted, total)
    }

    // ---- writes ----

    /// Get (or lazily create) the hidden virtual account that tracks money
    /// others owe [userId] ("receivable") or [userId] owes others ("payable"),
    /// per currency. NOTE: unlike LedgerRepository.createAccount's fixed
    /// column list (matching the real PowerSyncAccountRepository.create()
    /// spec), this writes kind/include_in_net_worth directly -- because the
    /// real ensureVirtualAccount uses the GENERIC insertRow helper, not the
    /// repository's create(). Two different account-creation code paths for
    /// two different purposes, faithfully mirrored as two different column
    /// sets here.
    @discardableResult
    public func ensureVirtualAccount(userId: String, kind: String, currency: String) async throws -> String {
        if let existing = try await db.getOptional(
            sql: "SELECT id FROM accounts WHERE user_id = ? AND kind = ? AND currency = ? AND deleted_at IS NULL LIMIT 1",
            parameters: [userId, kind, currency],
            mapper: { cursor in try cursor.getString(name: "id") }
        ) {
            return existing
        }
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO accounts (id,user_id,name,type,currency,icon,color,is_archived,include_in_net_worth,allow_negative,kind,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [
                id, userId,
                kind == "receivable" ? "Owed to me" : "I owe",
                "cash", currency, nil,
                kind == "receivable" ? "#5f7a52" : "#a8503a",
                false, false, false, kind, ts, ts,
            ]
        )
        return id
    }

    /// Create a group/trip. Adds [userId] as owner; other members added directly.
    @discardableResult
    public func createGroup(
        userId: String, name: String, kind: String, currency: String,
        startDate: String? = nil, endDate: String? = nil, autoSplit: Bool = false,
        isDirect: Bool = false, memberUserIds: [String] = []
    ) async throws -> String {
        let groupId = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO split_groups (id,created_by,name,kind,is_direct,start_date,end_date,auto_split,default_mode,currency,archived,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [groupId, userId, name.trimmingCharacters(in: .whitespacesAndNewlines), kind, isDirect, startDate, endDate, autoSplit, "equal", currency, false, ts, ts]
        )
        try await db.execute(
            sql: "INSERT INTO split_group_members (id,group_id,user_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?)",
            parameters: [newId(), groupId, userId, "owner", ts, ts]
        )
        for uid in memberUserIds where uid != userId {
            try await db.execute(
                sql: "INSERT INTO split_group_members (id,group_id,user_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                parameters: [newId(), groupId, uid, "member", ts, ts]
            )
        }
        return groupId
    }

    /// Find (or create) the hidden 2-person group for a 1:1 split.
    @discardableResult
    public func getOrCreateDirectGroup(userId: String, otherUserId: String, otherName: String, currency: String) async throws -> String {
        if let existing = try await db.getOptional(
            sql: """
                SELECT g.id AS id FROM split_groups g
                WHERE g.is_direct = 1 AND g.deleted_at IS NULL
                  AND (SELECT COUNT(*) FROM split_group_members m WHERE m.group_id = g.id AND m.deleted_at IS NULL) = 2
                  AND (SELECT COUNT(*) FROM split_group_members m WHERE m.group_id = g.id AND m.deleted_at IS NULL AND m.user_id IN (?, ?)) = 2
                LIMIT 1
                """,
            parameters: [userId, otherUserId],
            mapper: { cursor in try cursor.getString(name: "id") }
        ) {
            return existing
        }
        return try await createGroup(
            userId: userId,
            name: otherName.isEmpty ? "Direct" : otherName,
            kind: "group",
            currency: currency,
            isDirect: true,
            memberUserIds: [otherUserId]
        )
    }

    /// Your private ledger projection of your share of a shared expense.
    /// Matches projectPersonal() exactly.
    private func projectPersonal(
        userId: String, currency: String, myShare: Int64, myPaid: Int64, myAccountId: String?,
        expenseId: String, categoryId: String?, description: String?, note: String?, occurredAt: String
    ) async throws {
        let paidToOwn = min(myPaid, myShare)
        let underpay = max(0, myShare - myPaid)
        let overpay = max(0, myPaid - myShare)

        func post(_ txId: String, _ role: String) async throws {
            try await db.execute(
                sql: "INSERT INTO expense_postings (id,user_id,expense_id,transaction_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                parameters: [newId(), userId, expenseId, txId, role, nowIso(), nowIso()]
            )
        }

        if paidToOwn > 0, let myAccountId {
            let tx = try await ledger.createTransaction(userId: userId, accountId: myAccountId, type: "expense", amount: money(paidToOwn, currency), occurredAt: occurredAt, categoryId: categoryId, note: note, description: description)
            try await post(tx.id, "own_share")
        }
        if underpay > 0 {
            let payable = try await ensureVirtualAccount(userId: userId, kind: "payable", currency: currency)
            let tx = try await ledger.createTransaction(userId: userId, accountId: payable, type: "expense", amount: money(underpay, currency), occurredAt: occurredAt, categoryId: categoryId, note: note, description: description)
            try await post(tx.id, "borrow")
        }
        if overpay > 0, let myAccountId {
            let tx = try await ledger.createTransaction(userId: userId, accountId: myAccountId, type: "expense", amount: money(overpay, currency), occurredAt: occurredAt, categoryId: categoryId, note: note, description: description)
            try await post(tx.id, "lend")
        }
    }

    /// Create a shared expense in a group, then project [userId]'s own share
    /// into their private ledger. Matches createSplitExpense() exactly.
    @discardableResult
    public func createSplitExpense(userId: String, input: SplitExpenseInput) async throws -> String {
        let currency = input.total.currency
        let shares = computeShares(input.mode, input.total, input.participants)
        var shareByUser: [String: Int64] = [:]
        var shareOrder: [String] = []
        for (i, p) in input.participants.enumerated() {
            if shareByUser[p.userId] == nil { shareOrder.append(p.userId) }
            shareByUser[p.userId, default: 0] += (i < shares.count ? shares[i] : 0)
        }
        var paidByUser: [String: Int64] = [:]
        var paidOrder: [String] = []
        for p in input.payers {
            if paidByUser[p.userId] == nil { paidOrder.append(p.userId) }
            paidByUser[p.userId, default: 0] += p.paid
        }

        let expenseId = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO expenses (id,group_id,created_by,description,amount,currency,occurred_at,split_mode,version,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [expenseId, input.groupId, userId, input.description, input.total.amount, currency, input.occurredAt, input.mode, 1, ts, ts]
        )
        var seenUsers: Set<String> = []
        var users: [String] = []
        for uid in shareOrder + paidOrder where !seenUsers.contains(uid) {
            seenUsers.insert(uid)
            users.append(uid)
        }
        for uid in users {
            try await db.execute(
                sql: """
                    INSERT INTO expense_participants (id,expense_id,group_id,user_id,paid_amount,share_amount,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?)
                    """,
                parameters: [newId(), expenseId, input.groupId, uid, paidByUser[uid] ?? 0, shareByUser[uid] ?? 0, ts, ts]
            )
        }

        let myShare = shareByUser[userId] ?? 0
        let myPaid = paidByUser[userId] ?? 0
        let myAccountId = input.payers.first { $0.userId == userId }?.accountId
        try await projectPersonal(userId: userId, currency: currency, myShare: myShare, myPaid: myPaid, myAccountId: myAccountId, expenseId: expenseId, categoryId: input.categoryId, description: input.description, note: input.note, occurredAt: input.occurredAt)

        return expenseId
    }

    /// The ledger transfer for whichever side is acting. Shared by settleUp
    /// and confirmSettlement. Matches postSettlementLeg() exactly.
    private func postSettlementLeg(userId: String, settlementId: String, amount: Int64, direction: String, accountId: String?, currency: String) async throws {
        guard let accountId, amount > 0 else { return }
        let txId: String
        if direction == "received" {
            let recv = try await ensureVirtualAccount(userId: userId, kind: "receivable", currency: currency)
            let tx = try await ledger.createTransaction(userId: userId, accountId: recv, type: "transfer", amount: money(amount, currency), occurredAt: nowIso(), note: "Settlement received", toAccountId: accountId)
            txId = tx.id
        } else {
            let pay = try await ensureVirtualAccount(userId: userId, kind: "payable", currency: currency)
            let tx = try await ledger.createTransaction(userId: userId, accountId: accountId, type: "transfer", amount: money(amount, currency), occurredAt: nowIso(), note: "Settlement paid", toAccountId: pay)
            txId = tx.id
        }
        try await db.execute(
            sql: "INSERT INTO expense_postings (id,user_id,settlement_id,transaction_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
            parameters: [newId(), userId, settlementId, txId, "settlement", nowIso(), nowIso()]
        )
    }

    /// Record a settlement. [status] defaults to "confirmed"; pass "pending"
    /// for a UPI-handoff flow with no delivery callback. [direction] is
    /// "received" | "paid". Matches settleUp() exactly.
    @discardableResult
    public func settleUp(
        userId: String, otherUserId: String, groupId: String, amount: Int64, direction: String,
        accountId: String?, currency: String, note: String? = nil, status: String = "confirmed",
        method: String? = nil, upiRef: String? = nil
    ) async throws -> String {
        let fromUser = direction == "received" ? otherUserId : userId
        let toUser = direction == "received" ? userId : otherUserId
        let settlementId = newId()
        let ts = nowIso()
        try await db.execute(
            sql: """
                INSERT INTO settlements (id,group_id,from_user,to_user,amount,currency,method,note,settled_at,created_by,status,confirmed_at,confirmed_by,upi_ref,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
            parameters: [
                settlementId, groupId, fromUser, toUser, amount, currency,
                method ?? (accountId != nil ? "account" : "none"),
                note, ts, userId, status,
                status == "confirmed" ? ts : nil,
                status == "confirmed" ? userId : nil,
                upiRef, ts, ts,
            ]
        )
        try await postSettlementLeg(userId: userId, settlementId: settlementId, amount: amount, direction: direction, accountId: accountId, currency: currency)
        return settlementId
    }

    /// The payee confirms the money arrived: flip to "confirmed" and post
    /// THEIR leg. Matches confirmSettlement() exactly.
    public func confirmSettlement(userId: String, settlement: PendingSettlement, accountId: String?) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE settlements SET status = ?, confirmed_at = ?, confirmed_by = ?, updated_at = ? WHERE id = ?",
            parameters: ["confirmed", ts, userId, ts, settlement.id]
        )
        try await postSettlementLeg(userId: userId, settlementId: settlement.id, amount: settlement.amount, direction: "received", accountId: accountId, currency: settlement.currency)
    }

    /// The payee says it never arrived. Marks the settlement "disputed"
    /// (removed from balance netting) without unwinding the payer's
    /// original transfer. Matches disputeSettlement() exactly.
    public func disputeSettlement(userId: String, settlementId: String, note: String? = nil) async throws {
        let ts = nowIso()
        try await db.execute(
            sql: "UPDATE settlements SET status = ?, confirmed_at = ?, confirmed_by = ?, note = ?, updated_at = ? WHERE id = ?",
            parameters: ["disputed", ts, userId, note ?? "Recipient reported it didn't arrive", ts, settlementId]
        )
    }
}
