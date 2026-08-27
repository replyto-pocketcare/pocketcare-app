import Foundation
import Domain
import PowerSync
import Supabase

/**
 The assistant's side of the database: durable memory, chat threads, and
 executing a confirmed tool call.

 Ported from `executeTool` and `loadMemory` in
 `apps/web/src/assistant/tools.ts`. Deciding whether a call is worth showing, and
 what the confirm card says, is Domain's job and is vector-pinned; this is the
 half that actually writes to the ledger, and it runs only AFTER the user has
 authorised it.

 Every write goes through the repository that owns that table rather than a raw
 INSERT of its own. That matters most for `record_transaction`:
 `LedgerRepository.createTransaction` carries the overdraft guard and the
 transfer/items validation, and a tool that bypassed it would let the model write
 rows the user's own Add Transaction screen would have refused.

 Mirrors Android's AssistantRepository.kt.
 */

/**
 What the Edge Function answered.

 Exactly one side is set. A nil `content` with a nil `error` is the "no content
 and no reason" case web renders as its default apology.
 */
public struct AssistantTurnResponse: Sendable {
    public let content: [AssistantContent]?
    public let error: String?
    public init(content: [AssistantContent]? = nil, error: String? = nil) {
        self.content = content
        self.error = error
    }
}

public struct AssistantThread: Equatable, Sendable {
    public let id: String
    public let title: String?
    public let updatedAt: String
}

public struct AssistantChatMessage: Equatable, Sendable {
    public let id: String
    public let threadId: String
    /// "user" | "assistant" | "action".
    public let role: String
    public let content: String
    public let createdAt: String
}

/**
 The longest memory note kept, in characters.

 Web's `notes.slice(-4000)` keeps the TAIL, so the oldest facts fall off first —
 which is the right end to drop from, and is reproduced rather than
 reinterpreted.
 */
private let memoryMaxChars = 4000

/// One remembered fact, truncated. Web's `.slice(0, 200)`.
private let memoryFactMaxChars = 200

/// Web's `["savings", "current", "cash"].includes(a.type)`.
private let liquidAccountTypes: Set<String> = ["savings", "current", "cash"]

/// Web averages over three months of transactions.
private let averageMonths = 3.0

/// Six calendar months of income vs expense, for the trend the model may chart.
private let cashflowMonths = 6

private let topCategoryLimit: Int64 = 8

/// Web's spelling, which is NOT the analyzer's "Uncategorised". Both reproduced as-is.
private let uncategorizedLabel = "Uncategorized"

/// Web's `threshold_pct: 80` on an assistant-created budget.
private let budgetDefaultThresholdPct = 80

/**
 Web's `major()`: `Math.round(minor) / 100`.

 This is web bug #8's SIXTH site and it is reproduced, not fixed. Unlike the
 parser sites, this number is not stored anywhere — it goes into a prompt and is
 read by a model. Fixing it here with `toMajor()` would make a JPY user's phone
 send a different snapshot than their browser for the same ledger, and the
 assistant would answer differently on each. Recorded against #8.
 */
private func summaryMajor(_ minor: Double) -> Double { jsRound(minor) / 100 }

/// `+(x).toFixed(2)` — rounded to two decimals and back to a number.
private func jsToFixed2Number(_ x: Double) -> Double {
    let negative = x < 0
    let v = negative ? -x : x
    let exact = String(format: "%.20f", v)
    guard let dot = exact.firstIndex(of: "."), let whole = Int64(exact[exact.startIndex..<dot]) else { return x }
    let frac = Array(exact[exact.index(after: dot)...])
    var hundredths = (frac.first?.wholeNumberValue ?? 0) * 10 + (frac.count > 1 ? (frac[1].wholeNumberValue ?? 0) : 0)
    if frac.count > 2, frac[2] >= "5" { hundredths += 1 }
    var units = whole
    if hundredths == 100 { hundredths = 0; units += 1 }
    let result = Double(units) + Double(hundredths) / 100
    return negative ? -result : result
}

/**
 A subscription's `next_renewal`, which is a date on some rows and a timestamp on
 others depending on which client wrote it.
 */
private func parseRenewalDate(_ raw: String, calendar: Calendar) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: raw) { return d }
    let plain = ISO8601DateFormatter()
    if let d = plain.date(from: raw) { return d }
    let dayOnly = DateFormatter()
    dayOnly.calendar = calendar
    dayOnly.timeZone = calendar.timeZone
    dayOnly.locale = Locale(identifier: "en_US_POSIX")
    dayOnly.dateFormat = "yyyy-MM-dd"
    return dayOnly.date(from: raw)
}

public final class AssistantRepository: @unchecked Sendable {
    private let db: PowerSyncDatabaseProtocol
    private let client: SupabaseClient
    private let ledgerRepository: LedgerRepository
    private let goalsRepository: GoalsRepository
    private let budgetRepository: BudgetRepository
    private let subscriptionsRepository: SubscriptionsRepository
    private let splitsRepository: SplitsRepository

    public init(
        db: PowerSyncDatabaseProtocol,
        client: SupabaseClient,
        ledgerRepository: LedgerRepository,
        goalsRepository: GoalsRepository,
        budgetRepository: BudgetRepository,
        subscriptionsRepository: SubscriptionsRepository,
        splitsRepository: SplitsRepository
    ) {
        self.db = db
        self.client = client
        self.ledgerRepository = ledgerRepository
        self.goalsRepository = goalsRepository
        self.budgetRepository = budgetRepository
        self.subscriptionsRepository = subscriptionsRepository
        self.splitsRepository = splitsRepository
    }

    // MARK: - memory

    /// Durable facts the assistant has learned, for the system prompt.
    public func loadMemory(userId: String) async throws -> String {
        let notes: String? = try await db.getOptional(
            sql: "SELECT notes FROM assistant_memory WHERE user_id = ? LIMIT 1",
            parameters: [userId],
            mapper: { try $0.getString(name: "notes") }
        )
        return (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - threads

    public func watchThreads(userId: String) throws -> AsyncThrowingStream<[AssistantThread], Error> {
        try db.watch(
            sql: """
                SELECT id, title, updated_at FROM assistant_threads
                WHERE user_id = ? AND deleted_at IS NULL
                ORDER BY updated_at DESC
                """,
            parameters: [userId],
            mapper: { cursor in
                AssistantThread(
                    id: try cursor.getString(name: "id"),
                    title: try cursor.getStringOptional(name: "title"),
                    updatedAt: try cursor.getString(name: "updated_at")
                )
            }
        )
    }

    public func watchMessages(threadId: String) throws -> AsyncThrowingStream<[AssistantChatMessage], Error> {
        try db.watch(
            sql: """
                SELECT id, thread_id, role, content, created_at FROM assistant_messages
                WHERE thread_id = ?
                ORDER BY created_at
                """,
            parameters: [threadId],
            mapper: { cursor in
                AssistantChatMessage(
                    id: try cursor.getString(name: "id"),
                    threadId: try cursor.getString(name: "thread_id"),
                    role: try cursor.getString(name: "role"),
                    content: try cursor.getString(name: "content"),
                    createdAt: try cursor.getString(name: "created_at")
                )
            }
        )
    }

    public func createThread(userId: String, title: String?) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.execute(
            sql: "INSERT INTO assistant_threads (id,user_id,title,created_at,updated_at) VALUES (?,?,?,?,?)",
            parameters: [id, userId, title, ts, ts]
        )
        return id
    }

    /**
     Append one message and bump its thread.

     Both in ONE transaction: a message whose thread did not move would sort to
     the bottom of the list it was just added to, and a thread bumped without its
     message would show a time with nothing behind it.
     */
    @discardableResult
    public func appendMessage(userId: String, threadId: String, role: String, content: String) async throws -> String {
        let id = newId()
        let ts = nowIso()
        try await db.writeTransaction { tx in
            _ = try tx.execute(
                sql: "INSERT INTO assistant_messages (id,user_id,thread_id,role,content,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                parameters: [id, userId, threadId, role, content, ts, ts]
            )
            _ = try tx.execute(
                sql: "UPDATE assistant_threads SET updated_at = ? WHERE id = ?",
                parameters: [ts, threadId]
            )
        }
        return id
    }

    public func deleteThread(threadId: String) async throws {
        try await softDelete(db: db, table: "assistant_threads", id: threadId)
    }

    // MARK: - the model call

    /**
     Ask the model. Ported from `callModel` in AssistantChat.tsx.

     The Edge Function ALWAYS answers HTTP 200 and carries failure in the body's
     `error`, which is why this returns a result rather than throwing: quota
     exhaustion, a missing API key and a prompt-injection screen are all ordinary
     answers the chat has to render, not exceptions.

     `system` is sent as an ARRAY of blocks, each marked cacheable. That is not
     decoration — PERSONA is ~8.6KB and identical on every request, so without
     the cache marker it is re-billed on every turn of a multi-step tool
     exchange. Web marks the last TOOL cacheable for the same reason.
     */
    public func callModel(
        systemBlocks: [String],
        messages: [ApiMessage],
        maxTokens: Int = assistantMaxTokens
    ) async -> AssistantTurnResponse {
        // `AnyJSON`, not `[String: Any]`: FunctionInvokeOptions takes
        // `some Encodable`, and a bare `Any` dictionary is not one. Passing the
        // serialised bytes instead would work but would be sent as
        // `application/octet-stream`, which is a different request.
        let body: AnyJSON = .object([
            "system": .array(systemBlocks.map { text in
                .object([
                    "type": .string("text"),
                    "text": .string(text),
                    "cache_control": .object(["type": .string("ephemeral")]),
                ])
            }),
            "messages": .array(trimAssistantHistory(messages).map(requestJson)),
            "tools": .array(assistantTools.enumerated().map { index, tool in
                var out: JSONObject = [
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    // The schema was generated as a STRING precisely so it could
                    // go back over the wire unchanged.
                    "input_schema": (try? JSONDecoder().decode(
                        AnyJSON.self, from: Foundation.Data(tool.inputSchema.utf8)
                    )) ?? .object([:]),
                ]
                if index == assistantTools.count - 1 {
                    out["cache_control"] = .object(["type": .string("ephemeral")])
                }
                return .object(out)
            }),
            "max_tokens": .integer(maxTokens),
        ])

        do {
            let raw: Foundation.Data = try await client.functions.invoke(
                "assistant",
                options: FunctionInvokeOptions(body: body)
            ) { data, _ in data }
            guard let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                return AssistantTurnResponse()
            }
            if let error = root["error"] as? String { return AssistantTurnResponse(error: error) }
            let content = (root["content"] as? [Any])?.compactMap(assistantContent(from:))
            return AssistantTurnResponse(content: content)
        } catch let error as FunctionsError {
            if case let .httpError(_, data) = error,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = root["error"] as? String {
                return AssistantTurnResponse(error: message)
            }
            return AssistantTurnResponse(error: error.localizedDescription)
        } catch {
            return AssistantTurnResponse(error: error.localizedDescription)
        }
    }

    // MARK: - tool execution

    /**
     Run a tool the user has confirmed. Returns a line for the transcript.

     Failure is a RESULT, not a thrown error, and the strings are web's. The
     model reads this back and has to be able to tell "no goal by that name" from
     "no account to record into" — an error would reach it as a generic failure
     and it would retry the same call.
     */
    public func executeTool(
        userId: String,
        name: String,
        input: ToolInput,
        baseCurrency: String
    ) async throws -> String {
        func str(_ key: String) -> String? {
            if case let .str(v) = input[key] { return v }
            return nil
        }
        func num(_ key: String) -> Double {
            if case let .num(v) = input[key] { return v }
            return 0
        }
        func flag(_ key: String) -> Bool {
            if case let .bool(v) = input[key] { return v }
            return false
        }

        switch name {
        case "create_goal":
            let cur = str("currency") ?? baseCurrency
            let id = try await goalsRepository.create(
                userId: userId,
                name: (str("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                targetAmount: fromMajor(num("target_amount"), cur).amount,
                currency: cur,
                isEmergencyFund: false,
                priority: 0,
                // Web inserts no alert time at all; this repository's create()
                // requires one, and the empty string is what every other caller
                // passes for "none".
                alertTimeUtc: ""
            )
            return "Created goal \"\(str("name") ?? "")\" (id \(id))."

        case "create_budget":
            let cur = str("currency") ?? baseCurrency
            let id = try await budgetRepository.create(
                userId: userId,
                name: (str("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                period: str("period") ?? "",
                // Web's assistant sets neither, and a budget with a period but
                // no window is what every non-assistant caller creates too.
                startDate: nil,
                endDate: nil,
                limitAmount: fromMajor(num("limit_amount"), cur).amount,
                currency: cur,
                thresholdPct: budgetDefaultThresholdPct,
                alertTimeUtc: ""
            )
            return "Created budget \"\(str("name") ?? "")\" (id \(id))."

        case "reserve_to_goal":
            let wanted = (str("goal_name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // lower(name) = lower(?), matching web: the model spells the goal
            // back the way the USER said it, not the way it is stored.
            let goal: (String, String)? = try await db.getOptional(
                sql: "SELECT id, currency FROM goals WHERE deleted_at IS NULL AND lower(name) = lower(?) LIMIT 1",
                parameters: [wanted],
                mapper: { (try $0.getString(name: "id"), try $0.getString(name: "currency")) }
            )
            guard let goal else { return "No goal named \"\(wanted)\" was found. Create it first." }
            let source: String? = try await db.getOptional(
                sql: """
                    SELECT id FROM accounts
                    WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0
                      AND type IN ('savings','current','cash')
                    ORDER BY created_at LIMIT 1
                    """,
                parameters: [],
                mapper: { try $0.getString(name: "id") }
            )
            guard let source else { return "No savings/current/cash account to reserve from." }
            try await goalsRepository.createAllocation(
                userId: userId,
                goalId: goal.0,
                sourceAccountId: source,
                amountBlocked: fromMajor(num("amount"), goal.1).amount
            )
            return "Reserved \(goal.1) \(jsonNumber(num("amount"))) toward \"\(wanted)\"."

        case "record_transaction":
            let type = str("type") == "income" ? "income" : "expense"
            var account: (String, String)?
            if let named = str("account")?.trimmingCharacters(in: .whitespacesAndNewlines), !named.isEmpty {
                account = try await db.getOptional(
                    sql: """
                        SELECT id, currency FROM accounts
                        WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real' AND lower(name) = lower(?)
                        LIMIT 1
                        """,
                    parameters: [named],
                    mapper: { (try $0.getString(name: "id"), try $0.getString(name: "currency")) }
                )
            }
            if account == nil {
                account = try await db.getOptional(
                    sql: """
                        SELECT id, currency FROM accounts
                        WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real'
                        ORDER BY created_at LIMIT 1
                        """,
                    parameters: [],
                    mapper: { (try $0.getString(name: "id"), try $0.getString(name: "currency")) }
                )
            }
            guard let account else { return "No account to record into — add an account first." }
            var categoryId: String?
            if let wanted = str("category")?.trimmingCharacters(in: .whitespacesAndNewlines), !wanted.isEmpty {
                categoryId = try await db.getOptional(
                    sql: "SELECT id FROM categories WHERE deleted_at IS NULL AND lower(name) = lower(?) LIMIT 1",
                    parameters: [wanted],
                    mapper: { try $0.getString(name: "id") }
                )
            }
            let description = str("description")?.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await ledgerRepository.createTransaction(
                userId: userId,
                accountId: account.0,
                type: type,
                amount: fromMajor(num("amount"), account.1),
                occurredAt: nowIso(),
                categoryId: categoryId,
                description: (description?.isEmpty ?? true) ? nil : description
            )
            return "Recorded \(type) of \(account.1) \(jsonNumber(num("amount")))."

        case "create_subscription":
            let id = try await subscriptionsRepository.create(
                userId: userId,
                name: (str("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                amount: fromMajor(num("amount"), baseCurrency).amount,
                currency: baseCurrency,
                billingCycle: str("billing_cycle") ?? ""
            )
            return "Added subscription \"\(str("name") ?? "")\" (id \(id))."

        case "create_group":
            let kind = str("kind") == "trip" ? "trip" : "group"
            let start = str("start_date")
            let end = str("end_date")
            let id = try await splitsRepository.createGroup(
                userId: userId,
                name: (str("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                currency: baseCurrency,
                startDate: start,
                endDate: end,
                // Auto-split needs BOTH dates, not just the flag: an undated
                // group has no window to auto-split inside.
                autoSplit: flag("auto_split") && !(start?.isEmpty ?? true) && !(end?.isEmpty ?? true)
            )
            var dates = ""
            if let start, !start.isEmpty {
                let tail = (end?.isEmpty ?? true) ? "" : "–\(end!)"
                dates = " (\(start)\(tail))"
            }
            return "Created \(kind) \"\(str("name") ?? "")\"\(dates) (id \(id)). Invite people from Groups & trips."

        case "remember":
            let fact = String((str("fact") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(memoryFactMaxChars))
            if fact.isEmpty { return "Nothing to remember." }
            let existing: (String, String)? = try await db.getOptional(
                sql: "SELECT id, notes FROM assistant_memory WHERE user_id = ? LIMIT 1",
                parameters: [userId],
                mapper: { (try $0.getString(name: "id"), try $0.getString(name: "notes")) }
            )
            let ts = nowIso()
            if let existing {
                let notes = (existing.1.isEmpty ? "" : existing.1 + "\n") + "- " + fact
                try await db.execute(
                    // suffix, not prefix: the OLDEST facts fall off first, which
                    // is web's `slice(-4000)` and the right end to drop from.
                    sql: "UPDATE assistant_memory SET notes = ?, updated_at = ? WHERE id = ?",
                    parameters: [String(notes.suffix(memoryMaxChars)), ts, existing.0]
                )
            } else {
                try await db.execute(
                    sql: "INSERT INTO assistant_memory (id,user_id,notes,created_at,updated_at) VALUES (?,?,?,?,?)",
                    parameters: [newId(), userId, "- " + fact, ts, ts]
                )
            }
            return "Saved to memory."

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - the snapshot

    /**
     Build the aggregate snapshot the assistant is given.

     Ported from `buildFinancialSummary` in `apps/web/src/assistant/summary.ts`.
     **Aggregates only** — no merchant names, no dates of individual spends, no
     counterparties. That is the claim web's header makes and the reason this
     returns a `FinancialSummary` rather than anything that could carry a row.

     `todayIso` and `now` are passed IN rather than read here, because a function
     that reads the clock cannot be tested against a fixture — the same rule
     every other date-sensitive port in this repo follows.
     */
    public func buildFinancialSummary(
        userId: String,
        baseCurrency: String,
        todayIso: String,
        now: Date
    ) async throws -> FinancialSummary {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let isoPlain = ISO8601DateFormatter()

        let threeMonthsAgo = isoPlain.string(from: calendar.date(byAdding: .month, value: -3, to: now)!)
        let sixtyDaysOn = calendar.date(byAdding: .day, value: 60, to: now)!

        // ---- accounts + liquid savings ----
        let accountRows: [(String, String, String, String)] = try await db.getAll(
            sql: """
                SELECT id, name, type, currency FROM accounts
                WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0
                ORDER BY created_at
                """,
            parameters: [],
            mapper: {
                (
                    try $0.getString(name: "id"),
                    try $0.getString(name: "name"),
                    try $0.getString(name: "type"),
                    try $0.getString(name: "currency")
                )
            }
        )
        var accounts: [SummaryAccount] = []
        var liquidSavings = 0.0
        for (id, name, type, currency) in accountRows {
            let balanceMajor = toMajor(try await ledgerRepository.accountBalance(accountId: id))
            accounts.append(SummaryAccount(id: id, name: name, type: type, currency: currency, balance: balanceMajor))
            // Only the BASE currency counts toward "liquid savings": summing a
            // dollar balance into a rupee total would be a wrong number stated
            // confidently, which is the worst kind for a model to reason from.
            if liquidAccountTypes.contains(type) && currency == baseCurrency { liquidSavings += balanceMajor }
        }

        // ---- three-month averages ----
        let flow: [(String, Int64)] = try await db.getAll(
            sql: """
                SELECT type, SUM(amount) as total FROM transactions
                WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= ?
                GROUP BY type
                """,
            parameters: [threeMonthsAgo],
            mapper: { (try $0.getString(name: "type"), try $0.getInt64(name: "total")) }
        )
        let income = flow.first { $0.0 == "income" }?.1 ?? 0
        let expense = flow.first { $0.0 == "expense" }?.1 ?? 0
        let avgMonthlyIncome = summaryMajor(Double(income) / averageMonths)
        let avgMonthlyExpense = summaryMajor(Double(expense) / averageMonths)

        // ---- six months of cashflow ----
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let sixAgo = isoPlain.string(from: calendar.date(byAdding: .month, value: -(cashflowMonths - 1), to: firstOfMonth)!)
        let monthRows: [(String, String, Int64)] = try await db.getAll(
            sql: """
                SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total FROM transactions
                WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= ?
                GROUP BY ym, type
                """,
            parameters: [sixAgo],
            mapper: {
                (try $0.getString(name: "ym"), try $0.getString(name: "type"), try $0.getInt64(name: "total"))
            }
        )
        let months: [String] = (0..<cashflowMonths).reversed().map { back in
            let m = calendar.date(byAdding: .month, value: -back, to: firstOfMonth)!
            let parts = calendar.dateComponents([.year, .month], from: m)
            return String(format: "%04d-%02d", parts.year!, parts.month!)
        }
        var incomeByMonth: [String: Double] = [:]
        var expenseByMonth: [String: Double] = [:]
        for (ym, type, total) in monthRows where months.contains(ym) {
            if type == "income" { incomeByMonth[ym] = summaryMajor(Double(total)) }
            else { expenseByMonth[ym] = summaryMajor(Double(total)) }
        }
        let monthlyCashflow = months.map {
            SummaryMonth(ym: $0, income: incomeByMonth[$0] ?? 0, expense: expenseByMonth[$0] ?? 0)
        }

        // ---- top categories ----
        let topCategories: [SummaryCategory] = try await db.getAll(
            sql: """
                SELECT c.name as name, SUM(t.amount) as total
                FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
                WHERE t.deleted_at IS NULL AND t.type = 'expense' AND t.occurred_at >= ?
                GROUP BY t.category_id ORDER BY total DESC LIMIT ?
                """,
            parameters: [threeMonthsAgo, topCategoryLimit],
            mapper: { cursor in
                // Web's `r.name || "Uncategorized"` — the American spelling,
                // which differs from the analyzer's "Uncategorised". Both are
                // reproduced as-is; making them agree is a WEB change.
                let raw = try cursor.getStringOptional(name: "name")
                let name = (raw?.isEmpty ?? true) ? uncategorizedLabel : raw!
                return SummaryCategory(name: name, amount: summaryMajor(Double(try cursor.getInt64(name: "total"))))
            }
        )

        // ---- fixed monthly obligations ----
        var obligations: Int64 = 0
        let subs: [(Int64, String)] = try await db.getAll(
            sql: "SELECT amount, billing_cycle FROM subscriptions WHERE is_active = 1 AND deleted_at IS NULL",
            parameters: [],
            mapper: { (try $0.getInt64(name: "amount"), try $0.getStringOptional(name: "billing_cycle") ?? "") }
        )
        for (amount, cycle) in subs { obligations += monthlyEquivalent(amount, cycle) }
        let emis: [Int64] = try await db.getAll(
            sql: "SELECT emi_amount FROM loans WHERE deleted_at IS NULL AND emi_amount IS NOT NULL",
            parameters: [],
            mapper: { try $0.getInt64(name: "emi_amount") }
        )
        for emi in emis { obligations += emi }
        let commitments: [(Int64, String)] = try await db.getAll(
            sql: "SELECT amount, frequency FROM recurring_commitments WHERE deleted_at IS NULL",
            parameters: [],
            mapper: { (try $0.getInt64(name: "amount"), try $0.getStringOptional(name: "frequency") ?? "") }
        )
        for (amount, frequency) in commitments { obligations += monthlyEquivalent(amount, frequency) }

        // ---- goals ----
        let goalRows: [(String, String, Int64, String)] = try await db.getAll(
            sql: "SELECT id, name, target_amount, currency FROM goals WHERE deleted_at IS NULL",
            parameters: [],
            mapper: {
                (
                    try $0.getString(name: "id"),
                    try $0.getString(name: "name"),
                    try $0.getInt64(name: "target_amount"),
                    try $0.getString(name: "currency")
                )
            }
        )
        let savedRows: [(String, Int64)] = try await db.getAll(
            sql: "SELECT goal_id, SUM(amount_blocked) as saved FROM goal_allocations WHERE deleted_at IS NULL GROUP BY goal_id",
            parameters: [],
            mapper: { (try $0.getString(name: "goal_id"), try $0.getInt64(name: "saved")) }
        )
        let savedByGoal = Dictionary(savedRows, uniquingKeysWith: { a, _ in a })
        let goals = goalRows.map { id, name, target, currency in
            SummaryGoal(
                name: name,
                target: summaryMajor(Double(target)),
                saved: summaryMajor(Double(savedByGoal[id] ?? 0)),
                currency: currency
            )
        }

        // ---- upcoming renewals ----
        let renewals: [SummaryUpcoming] = try await db.getAll(
            sql: """
                SELECT name, next_renewal, amount, currency FROM subscriptions
                WHERE is_active = 1 AND deleted_at IS NULL AND next_renewal IS NOT NULL
                """,
            parameters: [],
            mapper: { cursor in
                SummaryUpcoming(
                    name: try cursor.getStringOptional(name: "name") ?? "",
                    date: try cursor.getString(name: "next_renewal"),
                    amount: summaryMajor(Double(try cursor.getInt64(name: "amount"))),
                    currency: try cursor.getStringOptional(name: "currency") ?? baseCurrency
                )
            }
        )
        let upcoming = renewals.filter { row in
            guard let at = parseRenewalDate(row.date, calendar: calendar) else { return false }
            return at >= now && at <= sixtyDaysOn
        }.sorted { $0.date < $1.date }

        // ---- splits ----
        let participantRows: [(String, Party)] = try await db.getAll(
            sql: """
                SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants
                WHERE deleted_at IS NULL
                """,
            parameters: [],
            mapper: { cursor in
                (
                    try cursor.getString(name: "expense_id"),
                    Party(
                        userId: try cursor.getString(name: "user_id"),
                        share: try cursor.getInt64(name: "share_amount"),
                        paid: try cursor.getInt64(name: "paid_amount")
                    )
                )
            }
        )
        let settlements: [(String, String, Int64)] = try await db.getAll(
            sql: """
                SELECT from_user, to_user, amount FROM settlements
                WHERE deleted_at IS NULL AND status <> 'disputed'
                """,
            parameters: [],
            mapper: {
                (
                    try $0.getString(name: "from_user"),
                    try $0.getString(name: "to_user"),
                    try $0.getInt64(name: "amount")
                )
            }
        )
        // Insertion-ordered on purpose: pairwiseEdges is order-sensitive at the
        // rounding boundary, and an unordered Dictionary here would make the
        // last paisa of a three-way split platform-specific.
        var expenseOrder: [String] = []
        var byExpense: [String: [Party]] = [:]
        for (expenseId, party) in participantRows {
            if byExpense[expenseId] == nil {
                byExpense[expenseId] = []
                expenseOrder.append(expenseId)
            }
            byExpense[expenseId]?.append(party)
        }
        var netOrder: [String] = []
        var net: [String: Int64] = [:]
        func bump(_ id: String, _ delta: Int64) {
            if net[id] == nil { net[id] = 0; netOrder.append(id) }
            net[id]! += delta
        }
        for expenseId in expenseOrder {
            for edge in pairwiseEdges(byExpense[expenseId] ?? [], userId) { bump(edge.userId, edge.amount) }
        }
        for (from, to, amount) in settlements {
            if to == userId { bump(from, -amount) } else if from == userId { bump(to, amount) }
        }
        var owed: Int64 = 0
        var owe: Int64 = 0
        for id in netOrder {
            let n = net[id] ?? 0
            if n > 0 { owed += n } else { owe += -n }
        }
        let groupCount: Int64 = try await db.getOptional(
            sql: "SELECT COUNT(*) as c FROM split_groups WHERE deleted_at IS NULL AND IFNULL(is_direct,0)=0",
            parameters: [],
            mapper: { try $0.getInt64(name: "c") }
        ) ?? 0

        return FinancialSummary(
            baseCurrency: baseCurrency,
            today: todayIso,
            accounts: accounts,
            liquidSavings: liquidSavings,
            avgMonthlyIncome: avgMonthlyIncome,
            avgMonthlyExpense: avgMonthlyExpense,
            // `+(x).toFixed(2)`: web rounds the DIFFERENCE rather than
            // subtracting two already-rounded numbers, and the two disagree by a
            // paisa often enough to matter in a prompt.
            monthlySurplus: jsToFixed2Number(avgMonthlyIncome - avgMonthlyExpense),
            fixedMonthlyObligations: summaryMajor(Double(obligations)),
            goals: goals,
            upcoming: upcoming,
            splits: SummarySplits(owed: summaryMajor(Double(owed)), owe: summaryMajor(Double(owe)), groups: Int(groupCount)),
            monthlyCashflow: monthlyCashflow,
            topCategories: topCategories
        )
    }
}

// MARK: - wire format

/// Domain's own JSON tree into supabase-swift's `AnyJSON`, for a tool call's `input`.
private func wire(_ j: AssistantJson) -> AnyJSON {
    switch j {
    case let .str(v): return .string(v)
    case let .num(v): return .double(v)
    case let .bool(v): return .bool(v)
    case let .arr(v): return .array(v.map(wire))
    case let .obj(v): return .object(v.mapValues(wire))
    case .null: return .null
    }
}

private func domainJson(_ any: Any) -> AssistantJson {
    switch any {
    case is NSNull: return .null
    case let s as String: return .str(s)
    case let n as NSNumber:
        // NSNumber does not distinguish a Bool from 0/1 by type, only by its
        // ObjC encoding, and getting it wrong would turn `true` into 1.
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
        return .num(n.doubleValue)
    case let a as [Any]: return .arr(a.map(domainJson))
    case let o as [String: Any]: return .obj(o.mapValues(domainJson))
    default: return .null
    }
}

private func wire(_ block: AssistantContent) -> AnyJSON {
    switch block {
    case let .text(t):
        return .object(["type": .string("text"), "text": .string(t)])
    case let .use(u):
        return .object([
            "type": .string("tool_use"),
            "id": .string(u.id),
            "name": .string(u.name),
            "input": .object(u.input.mapValues(wire)),
        ])
    case let .result(id, content):
        return .object([
            "type": .string("tool_result"),
            "tool_use_id": .string(id),
            "content": .string(content),
        ])
    }
}

/**
 One message as the API wants it.

 `content` is EITHER a bare string or an array of blocks, never both. Sending an
 array where a string belongs is accepted; sending both is not, and mixing them
 across a conversation is what makes a window fail to open on a user turn.
 */
private func requestJson(_ m: ApiMessage) -> AnyJSON {
    if let text = m.textContent {
        return .object(["role": .string(m.role), "content": .string(text)])
    }
    return .object(["role": .string(m.role), "content": .array(m.blocks.map(wire))])
}

/// A block the model sent back. Unknown types are dropped rather than guessed at.
private func assistantContent(from any: Any) -> AssistantContent? {
    guard let o = any as? [String: Any] else { return nil }
    switch o["type"] as? String {
    case "text":
        return .text(o["text"] as? String ?? "")
    case "tool_use":
        let input: ToolInput
        if case let .obj(args) = domainJson(o["input"] ?? [String: Any]()) { input = args } else { input = [:] }
        return .use(ToolUse(id: o["id"] as? String ?? "", name: o["name"] as? String ?? "", input: input))
    case "tool_result":
        return .result(toolUseId: o["tool_use_id"] as? String ?? "", content: o["content"] as? String ?? "")
    default:
        return nil
    }
}

