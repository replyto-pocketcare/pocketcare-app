package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.sanvya.app.domain.assistant.ASSISTANT_MAX_TOKENS
import com.sanvya.app.domain.assistant.ASSISTANT_TOOLS
import com.sanvya.app.domain.assistant.ApiMessage
import com.sanvya.app.domain.assistant.AssistantContent
import com.sanvya.app.domain.assistant.ToolUse
import com.sanvya.app.domain.assistant.trimAssistantHistory
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import com.powersync.db.SqlCursor
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.assistant.AssistantJson
import com.sanvya.app.domain.assistant.FinancialSummary
import com.sanvya.app.domain.assistant.SummaryAccount
import com.sanvya.app.domain.assistant.SummaryCategory
import com.sanvya.app.domain.assistant.SummaryGoal
import com.sanvya.app.domain.assistant.SummaryMonth
import com.sanvya.app.domain.assistant.SummarySplits
import com.sanvya.app.domain.assistant.SummaryUpcoming
import com.sanvya.app.domain.assistant.ToolInput
import com.sanvya.app.domain.finance.monthlyEquivalent
import com.sanvya.app.domain.js.jsRound
import com.sanvya.app.domain.js.jsonNumber
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.toMajor
import com.sanvya.app.domain.splitsmath.Party
import com.sanvya.app.domain.splitsmath.pairwiseEdges
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlinx.coroutines.flow.Flow

/**
 * The assistant's side of the database: durable memory, chat threads, and
 * executing a confirmed tool call.
 *
 * Ported from `executeTool` and `loadMemory` in
 * `apps/web/src/assistant/tools.ts`. Deciding whether a call is worth showing,
 * and what the confirm card says, is Domain's job and is vector-pinned; this is
 * the half that actually writes to the ledger, and it runs only AFTER the user
 * has authorised it.
 *
 * Every write goes through the repository that owns that table rather than a
 * raw INSERT of its own. That matters most for `record_transaction`:
 * [LedgerRepository.createTransaction] carries the overdraft guard and the
 * transfer/items validation, and a tool that bypassed it would let the model
 * write rows the user's own Add Transaction screen would have refused.
 *
 * Mirrors iOS's AssistantRepository.swift.
 */

data class AssistantThread(val id: String, val title: String?, val updatedAt: String)

/**
 * What the Edge Function answered.
 *
 * Exactly one side is set. A null [content] with a null [error] is the
 * "no content and no reason" case web renders as its default apology.
 */
data class AssistantTurnResponse(
    val content: List<AssistantContent>? = null,
    val error: String? = null,
)

data class AssistantMessage(
    val id: String,
    val threadId: String,
    /** "user" | "assistant" | "action". */
    val role: String,
    val content: String,
    val createdAt: String,
)

private fun threadMapper(c: SqlCursor) = AssistantThread(
    id = c.getString("id"),
    title = c.getStringOptional("title"),
    updatedAt = c.getString("updated_at"),
)

private fun messageMapper(c: SqlCursor) = AssistantMessage(
    id = c.getString("id"),
    threadId = c.getString("thread_id"),
    role = c.getString("role"),
    content = c.getString("content"),
    createdAt = c.getString("created_at"),
)

/**
 * The longest memory note kept, in characters.
 *
 * Web's `notes.slice(-4000)` keeps the TAIL, so the oldest facts fall off
 * first — which is the right end to drop from, and is reproduced rather than
 * reinterpreted.
 */
private const val MEMORY_MAX_CHARS = 4000

/** One remembered fact, truncated. Web's `.slice(0, 200)`. */
private const val MEMORY_FACT_MAX_CHARS = 200

class AssistantRepository(
    private val db: PowerSyncDatabase,
    private val client: SupabaseClient,
    private val ledgerRepository: LedgerRepository,
    private val goalsRepository: GoalsRepository,
    private val budgetRepository: BudgetRepository,
    private val subscriptionsRepository: SubscriptionsRepository,
    private val splitsRepository: SplitsRepository,
) {

    // ---- memory ----

    /** Durable facts the assistant has learned, for the system prompt. */
    suspend fun loadMemory(userId: String): String =
        db.getOptional(
            sql = "SELECT notes FROM assistant_memory WHERE user_id = ? LIMIT 1",
            parameters = listOf(userId),
            mapper = { it.getString("notes") },
        )?.trim().orEmpty()

    // ---- threads ----

    fun watchThreads(userId: String): Flow<List<AssistantThread>> = db.watch(
        sql = """
            SELECT id, title, updated_at FROM assistant_threads
            WHERE user_id = ? AND deleted_at IS NULL
            ORDER BY updated_at DESC
            """.trimIndent(),
        parameters = listOf(userId),
        mapper = ::threadMapper,
    )

    fun watchMessages(threadId: String): Flow<List<AssistantMessage>> = db.watch(
        sql = """
            SELECT id, thread_id, role, content, created_at FROM assistant_messages
            WHERE thread_id = ?
            ORDER BY created_at
            """.trimIndent(),
        parameters = listOf(threadId),
        mapper = ::messageMapper,
    )

    suspend fun createThread(userId: String, title: String?): String {
        val id = newId()
        val ts = nowIso()
        db.execute(
            sql = "INSERT INTO assistant_threads (id,user_id,title,created_at,updated_at) VALUES (?,?,?,?,?)",
            parameters = listOf(id, userId, title, ts, ts),
        )
        return id
    }

    /**
     * Append one message and bump its thread.
     *
     * Both in ONE transaction: a message whose thread did not move would sort
     * to the bottom of the list it was just added to, and a thread bumped
     * without its message would show a time with nothing behind it.
     */
    suspend fun appendMessage(userId: String, threadId: String, role: String, content: String): String {
        val id = newId()
        val ts = nowIso()
        db.writeTransaction { tx ->
            tx.execute(
                sql = "INSERT INTO assistant_messages (id,user_id,thread_id,role,content,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                parameters = listOf(id, userId, threadId, role, content, ts, ts),
            )
            tx.execute(
                sql = "UPDATE assistant_threads SET updated_at = ? WHERE id = ?",
                parameters = listOf(ts, threadId),
            )
        }
        return id
    }

    suspend fun deleteThread(threadId: String) = softDelete(db, "assistant_threads", threadId)

    // ---- the model call ----

    /**
     * Ask the model. Ported from `callModel` in AssistantChat.tsx.
     *
     * The Edge Function ALWAYS answers HTTP 200 and carries failure in the
     * body's `error`, which is why this returns a result rather than throwing:
     * quota exhaustion, a missing API key and a prompt-injection screen are all
     * ordinary answers the chat has to render, not exceptions.
     *
     * `system` is sent as an ARRAY of blocks, each marked cacheable. That is not
     * decoration — PERSONA is ~8.6KB and identical on every request, so without
     * the cache marker it is re-billed on every turn of a multi-step tool
     * exchange. Web marks the last TOOL cacheable for the same reason.
     */
    suspend fun callModel(
        systemBlocks: List<String>,
        messages: List<ApiMessage>,
        maxTokens: Int = ASSISTANT_MAX_TOKENS,
    ): AssistantTurnResponse {
        val body = buildJsonObject {
            put(
                "system",
                JsonArray(
                    systemBlocks.map { text ->
                        buildJsonObject {
                            put("type", "text")
                            put("text", text)
                            put("cache_control", buildJsonObject { put("type", "ephemeral") })
                        }
                    },
                ),
            )
            put("messages", JsonArray(trimAssistantHistory(messages).map { it.toRequestJson() }))
            put(
                "tools",
                JsonArray(
                    ASSISTANT_TOOLS.mapIndexed { index, tool ->
                        buildJsonObject {
                            put("name", tool.name)
                            put("description", tool.description)
                            // The schema was generated as a STRING precisely so
                            // it could go back over the wire unchanged.
                            put("input_schema", Json.parseToJsonElement(tool.inputSchema))
                            if (index == ASSISTANT_TOOLS.lastIndex) {
                                put("cache_control", buildJsonObject { put("type", "ephemeral") })
                            }
                        }
                    },
                ),
            )
            put("max_tokens", maxTokens)
        }

        val json: JsonObject = try {
            val response = client.functions.invoke(
                function = "assistant",
                body = body,
                headers = Headers.build { append(HttpHeaders.ContentType, "application/json") },
            )
            Json.parseToJsonElement(response.bodyAsText()).jsonObject
        } catch (e: RestException) {
            val parsed = runCatching { Json.parseToJsonElement(e.message.orEmpty()).jsonObject }.getOrNull()
            return AssistantTurnResponse(
                error = parsed?.get("error")?.jsonPrimitive?.contentOrNull ?: e.message,
            )
        } catch (e: Exception) {
            return AssistantTurnResponse(error = e.message)
        }

        json["error"]?.jsonPrimitive?.contentOrNull?.let { return AssistantTurnResponse(error = it) }
        val content = (json["content"] as? JsonArray)?.mapNotNull { it.toAssistantContent() }
        return AssistantTurnResponse(content = content)
    }

    // ---- tool execution ----

    private fun ToolInput.str(key: String): String? = (this[key] as? AssistantJson.Str)?.value
    private fun ToolInput.num(key: String): Double = (this[key] as? AssistantJson.Num)?.value ?: 0.0
    private fun ToolInput.flag(key: String): Boolean = (this[key] as? AssistantJson.Bool)?.value ?: false

    /**
     * Run a tool the user has confirmed. Returns a line for the transcript.
     *
     * Failure is a RESULT, not an exception, and the strings are web's. The
     * model reads this back and has to be able to tell "no goal by that name"
     * from "no account to record into" — an exception would reach it as a
     * generic failure and it would retry the same call.
     */
    suspend fun executeTool(
        userId: String,
        name: String,
        input: ToolInput,
        baseCurrency: String,
    ): String = when (name) {
        "create_goal" -> {
            val cur = input.str("currency") ?: baseCurrency
            goalsRepository.create(
                userId = userId,
                name = input.str("name").orEmpty().trim(),
                targetAmount = fromMajor(input.num("target_amount"), cur).amount,
                currency = cur,
                isEmergencyFund = false,
                priority = 0,
                // Web inserts no alert time at all; this repository's create()
                // requires one, and the empty string is what every other caller
                // passes for "none".
                alertTimeUtc = "",
            ).let { id -> "Created goal \"${input.str("name").orEmpty()}\" (id $id)." }
        }

        "create_budget" -> {
            val cur = input.str("currency") ?: baseCurrency
            val id = budgetRepository.create(
                userId = userId,
                name = input.str("name").orEmpty().trim(),
                period = input.str("period").orEmpty(),
                // Web's assistant sets neither, and a budget with a period but
                // no window is what every non-assistant caller creates too.
                startDate = null,
                endDate = null,
                limitAmount = fromMajor(input.num("limit_amount"), cur).amount,
                currency = cur,
                thresholdPct = BUDGET_DEFAULT_THRESHOLD_PCT,
                alertTimeUtc = "",
            )
            "Created budget \"${input.str("name").orEmpty()}\" (id $id)."
        }

        "reserve_to_goal" -> {
            val wanted = input.str("goal_name").orEmpty().trim()
            val goal = db.getOptional(
                // lower(name) = lower(?), matching web: the model spells the
                // goal back the way the USER said it, not the way it is stored.
                sql = "SELECT id, currency FROM goals WHERE deleted_at IS NULL AND lower(name) = lower(?) LIMIT 1",
                parameters = listOf(wanted),
                mapper = { it.getString("id") to it.getString("currency") },
            )
            if (goal == null) {
                "No goal named \"$wanted\" was found. Create it first."
            } else {
                val source = db.getOptional(
                    sql = """
                        SELECT id FROM accounts
                        WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0
                          AND type IN ('savings','current','cash')
                        ORDER BY created_at LIMIT 1
                        """.trimIndent(),
                    parameters = emptyList(),
                    mapper = { it.getString("id") },
                )
                if (source == null) {
                    "No savings/current/cash account to reserve from."
                } else {
                    goalsRepository.createAllocation(
                        userId = userId,
                        goalId = goal.first,
                        sourceAccountId = source,
                        amountBlocked = fromMajor(input.num("amount"), goal.second).amount,
                    )
                    "Reserved ${goal.second} ${jsonNumber(input.num("amount"))} toward \"$wanted\"."
                }
            }
        }

        "record_transaction" -> {
            val type = if (input.str("type") == "income") "income" else "expense"
            val named = input.str("account")?.trim()?.takeIf { it.isNotEmpty() }
            val account = (
                named?.let {
                    db.getOptional(
                        sql = """
                            SELECT id, currency FROM accounts
                            WHERE deleted_at IS NULL AND IFNULL(kind,'real')='real' AND lower(name) = lower(?)
                            LIMIT 1
                            """.trimIndent(),
                        parameters = listOf(it),
                        mapper = { c -> c.getString("id") to c.getString("currency") },
                    )
                }
                ) ?: db.getOptional(
                sql = """
                    SELECT id, currency FROM accounts
                    WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real'
                    ORDER BY created_at LIMIT 1
                    """.trimIndent(),
                parameters = emptyList(),
                mapper = { c -> c.getString("id") to c.getString("currency") },
            )
            if (account == null) {
                "No account to record into — add an account first."
            } else {
                val categoryId = input.str("category")?.trim()?.takeIf { it.isNotEmpty() }?.let { wanted ->
                    db.getOptional(
                        sql = "SELECT id FROM categories WHERE deleted_at IS NULL AND lower(name) = lower(?) LIMIT 1",
                        parameters = listOf(wanted),
                        mapper = { it.getString("id") },
                    )
                }
                ledgerRepository.createTransaction(
                    userId = userId,
                    accountId = account.first,
                    type = type,
                    amount = fromMajor(input.num("amount"), account.second),
                    occurredAt = nowIso(),
                    categoryId = categoryId,
                    description = input.str("description")?.trim()?.takeIf { it.isNotEmpty() },
                )
                "Recorded $type of ${account.second} ${jsonNumber(input.num("amount"))}."
            }
        }

        "create_subscription" -> {
            val id = subscriptionsRepository.create(
                userId = userId,
                name = input.str("name").orEmpty().trim(),
                amount = fromMajor(input.num("amount"), baseCurrency).amount,
                currency = baseCurrency,
                billingCycle = input.str("billing_cycle").orEmpty(),
                purchasedOn = null,
                nextRenewal = null,
            )
            "Added subscription \"${input.str("name").orEmpty()}\" (id $id)."
        }

        "create_group" -> {
            val kind = if (input.str("kind") == "trip") "trip" else "group"
            val start = input.str("start_date")
            val end = input.str("end_date")
            val id = splitsRepository.createGroup(
                userId = userId,
                name = input.str("name").orEmpty().trim(),
                kind = kind,
                currency = baseCurrency,
                startDate = start,
                endDate = end,
                // Auto-split needs BOTH dates, not just the flag: an undated
                // group has no window to auto-split inside.
                autoSplit = input.flag("auto_split") && !start.isNullOrEmpty() && !end.isNullOrEmpty(),
            )
            val dates = if (!start.isNullOrEmpty()) {
                " ($start${if (!end.isNullOrEmpty()) "–$end" else ""})"
            } else {
                ""
            }
            "Created $kind \"${input.str("name").orEmpty()}\"$dates (id $id). Invite people from Groups & trips."
        }

        "remember" -> {
            val fact = input.str("fact").orEmpty().trim().take(MEMORY_FACT_MAX_CHARS)
            if (fact.isEmpty()) {
                "Nothing to remember."
            } else {
                val existing = db.getOptional(
                    sql = "SELECT id, notes FROM assistant_memory WHERE user_id = ? LIMIT 1",
                    parameters = listOf(userId),
                    mapper = { it.getString("id") to it.getString("notes") },
                )
                val ts = nowIso()
                if (existing != null) {
                    val notes = (if (existing.second.isNotEmpty()) existing.second + "\n" else "") + "- $fact"
                    db.execute(
                        sql = "UPDATE assistant_memory SET notes = ?, updated_at = ? WHERE id = ?",
                        // takeLast, not take: the OLDEST facts fall off first,
                        // which is web's `slice(-4000)` and the right end to
                        // drop from.
                        parameters = listOf(notes.takeLast(MEMORY_MAX_CHARS), ts, existing.first),
                    )
                } else {
                    db.execute(
                        sql = "INSERT INTO assistant_memory (id,user_id,notes,created_at,updated_at) VALUES (?,?,?,?,?)",
                        parameters = listOf(newId(), userId, "- $fact", ts, ts),
                    )
                }
                "Saved to memory."
            }
        }

        else -> "Unknown tool: $name"
    }

    // ---- the snapshot ----

    /**
     * Build the aggregate snapshot the assistant is given.
     *
     * Ported from `buildFinancialSummary` in `apps/web/src/assistant/summary.ts`.
     * **Aggregates only** -- no merchant names, no dates of individual spends,
     * no counterparties. That is the claim web's header makes and the reason
     * this returns a [FinancialSummary] rather than anything that could carry a
     * row.
     *
     * `todayIso` and `nowMillis` are passed IN rather than read here, because a
     * function that reads the clock cannot be tested against a fixture -- the
     * same rule every other date-sensitive port in this repo follows.
     */
    suspend fun buildFinancialSummary(
        userId: String,
        baseCurrency: String,
        todayIso: String,
        nowMillis: Long,
    ): FinancialSummary {
        val zone = ZoneOffset.UTC
        val now = Instant.ofEpochMilli(nowMillis)
        val threeMonthsAgo = now.atZone(zone).minusMonths(3).toInstant().toString()
        val sixtyDaysOn = now.plus(60, ChronoUnit.DAYS)

        // ---- accounts + liquid savings ----
        val accountRows = db.getAll(
            sql = """
                SELECT id, name, type, currency FROM accounts
                WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0
                ORDER BY created_at
                """.trimIndent(),
            parameters = emptyList(),
            mapper = { c ->
                listOf(c.getString("id"), c.getString("name"), c.getString("type"), c.getString("currency"))
            },
        )
        val accounts = mutableListOf<SummaryAccount>()
        var liquidSavings = 0.0
        for (row in accountRows) {
            val (id, name, type, currency) = row
            val balanceMajor = toMajor(ledgerRepository.accountBalance(id))
            accounts.add(SummaryAccount(id, name, type, currency, balanceMajor))
            // Only the BASE currency counts toward "liquid savings": summing a
            // dollar balance into a rupee total would be a wrong number stated
            // confidently, which is the worst kind for a model to reason from.
            if (type in LIQUID_ACCOUNT_TYPES && currency == baseCurrency) liquidSavings += balanceMajor
        }

        // ---- three-month averages ----
        val flow = db.getAll(
            sql = """
                SELECT type, SUM(amount) as total FROM transactions
                WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= ?
                GROUP BY type
                """.trimIndent(),
            parameters = listOf(threeMonthsAgo),
            mapper = { c -> c.getString("type") to c.getLong("total") },
        )
        val income = flow.firstOrNull { it.first == "income" }?.second ?: 0L
        val expense = flow.firstOrNull { it.first == "expense" }?.second ?: 0L
        val avgMonthlyIncome = major(income.toDouble() / AVERAGE_MONTHS)
        val avgMonthlyExpense = major(expense.toDouble() / AVERAGE_MONTHS)

        // ---- six months of cashflow ----
        val firstOfMonth = now.atZone(zone).withDayOfMonth(1)
        val sixAgo = firstOfMonth.minusMonths((CASHFLOW_MONTHS - 1).toLong()).toInstant().toString()
        val monthRows = db.getAll(
            sql = """
                SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total FROM transactions
                WHERE deleted_at IS NULL AND type IN ('income','expense') AND occurred_at >= ?
                GROUP BY ym, type
                """.trimIndent(),
            parameters = listOf(sixAgo),
            mapper = { c -> Triple(c.getString("ym"), c.getString("type"), c.getLong("total")) },
        )
        val months = (CASHFLOW_MONTHS - 1 downTo 0).map { back ->
            val m = firstOfMonth.minusMonths(back.toLong())
            "%04d-%02d".format(Locale.ROOT, m.year, m.monthValue)
        }
        val incomeByMonth = mutableMapOf<String, Double>()
        val expenseByMonth = mutableMapOf<String, Double>()
        for ((ym, type, total) in monthRows) {
            if (ym !in months) continue
            if (type == "income") incomeByMonth[ym] = major(total.toDouble()) else expenseByMonth[ym] = major(total.toDouble())
        }
        val monthlyCashflow = months.map {
            SummaryMonth(it, incomeByMonth[it] ?: 0.0, expenseByMonth[it] ?: 0.0)
        }

        // ---- top categories ----
        val topCategories = db.getAll(
            sql = """
                SELECT c.name as name, SUM(t.amount) as total
                FROM transactions t LEFT JOIN categories c ON c.id = t.category_id
                WHERE t.deleted_at IS NULL AND t.type = 'expense' AND t.occurred_at >= ?
                GROUP BY t.category_id ORDER BY total DESC LIMIT ?
                """.trimIndent(),
            parameters = listOf(threeMonthsAgo, TOP_CATEGORY_LIMIT),
            mapper = { c ->
                SummaryCategory(
                    // Web's `r.name || "Uncategorized"` -- the American spelling,
                    // which differs from the analyzer's "Uncategorised". Both are
                    // reproduced as-is; making them agree is a WEB change.
                    name = c.getStringOptional("name")?.takeIf { it.isNotEmpty() } ?: UNCATEGORIZED_LABEL,
                    amount = major(c.getLong("total").toDouble()),
                )
            },
        )

        // ---- fixed monthly obligations ----
        var obligations = 0L
        db.getAll(
            sql = "SELECT amount, billing_cycle FROM subscriptions WHERE is_active = 1 AND deleted_at IS NULL",
            parameters = emptyList(),
            mapper = { c -> c.getLong("amount") to (c.getStringOptional("billing_cycle") ?: "") },
        ).forEach { obligations += monthlyEquivalent(it.first, it.second) }
        db.getAll(
            sql = "SELECT emi_amount FROM loans WHERE deleted_at IS NULL AND emi_amount IS NOT NULL",
            parameters = emptyList(),
            mapper = { c -> c.getLong("emi_amount") },
        ).forEach { obligations += it }
        db.getAll(
            sql = "SELECT amount, frequency FROM recurring_commitments WHERE deleted_at IS NULL",
            parameters = emptyList(),
            mapper = { c -> c.getLong("amount") to (c.getStringOptional("frequency") ?: "") },
        ).forEach { obligations += monthlyEquivalent(it.first, it.second) }

        // ---- goals ----
        val goalRows = db.getAll(
            sql = "SELECT id, name, target_amount, currency FROM goals WHERE deleted_at IS NULL",
            parameters = emptyList(),
            mapper = { c ->
                listOf(c.getString("id"), c.getString("name"), c.getLong("target_amount").toString(), c.getString("currency"))
            },
        )
        val savedByGoal = db.getAll(
            sql = "SELECT goal_id, SUM(amount_blocked) as saved FROM goal_allocations WHERE deleted_at IS NULL GROUP BY goal_id",
            parameters = emptyList(),
            mapper = { c -> c.getString("goal_id") to c.getLong("saved") },
        ).toMap()
        val goals = goalRows.map { (id, name, target, currency) ->
            SummaryGoal(
                name = name,
                target = major(target.toDouble()),
                saved = major((savedByGoal[id] ?: 0L).toDouble()),
                currency = currency,
            )
        }

        // ---- upcoming renewals ----
        val upcoming = db.getAll(
            sql = """
                SELECT name, next_renewal, amount, currency FROM subscriptions
                WHERE is_active = 1 AND deleted_at IS NULL AND next_renewal IS NOT NULL
                """.trimIndent(),
            parameters = emptyList(),
            mapper = { c ->
                SummaryUpcoming(
                    name = c.getStringOptional("name").orEmpty(),
                    date = c.getString("next_renewal"),
                    amount = major(c.getLong("amount").toDouble()),
                    currency = c.getStringOptional("currency") ?: baseCurrency,
                )
            },
        ).filter { row ->
            val at = runCatching { Instant.parse(row.date) }.getOrNull()
                ?: runCatching { LocalDate.parse(row.date).atStartOfDay(zone).toInstant() }.getOrNull()
                ?: return@filter false
            !at.isBefore(now) && !at.isAfter(sixtyDaysOn)
        }.sortedBy { it.date }

        // ---- splits ----
        val participants = db.getAll(
            sql = """
                SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants
                WHERE deleted_at IS NULL
                """.trimIndent(),
            parameters = emptyList(),
            mapper = { c ->
                c.getString("expense_id") to Party(c.getString("user_id"), c.getLong("share_amount"), c.getLong("paid_amount"))
            },
        )
        val settlements = db.getAll(
            sql = """
                SELECT from_user, to_user, amount FROM settlements
                WHERE deleted_at IS NULL AND status <> 'disputed'
                """.trimIndent(),
            parameters = emptyList(),
            mapper = { c -> Triple(c.getString("from_user"), c.getString("to_user"), c.getLong("amount")) },
        )
        // Insertion-ordered on purpose: pairwiseEdges is order-sensitive at the
        // rounding boundary, and a HashMap here would make the last paisa of a
        // three-way split platform-specific.
        val byExpense = LinkedHashMap<String, MutableList<Party>>()
        for ((expenseId, party) in participants) byExpense.getOrPut(expenseId) { mutableListOf() }.add(party)
        val net = LinkedHashMap<String, Long>()
        for ((_, parties) in byExpense) {
            for (edge in pairwiseEdges(parties, userId)) net[edge.userId] = (net[edge.userId] ?: 0L) + edge.amount
        }
        for ((from, to, amount) in settlements) {
            if (to == userId) net[from] = (net[from] ?: 0L) - amount
            else if (from == userId) net[to] = (net[to] ?: 0L) + amount
        }
        var owed = 0L
        var owe = 0L
        for (n in net.values) if (n > 0) owed += n else owe += -n
        val groupCount = db.getOptional(
            sql = "SELECT COUNT(*) as c FROM split_groups WHERE deleted_at IS NULL AND IFNULL(is_direct,0)=0",
            parameters = emptyList(),
            mapper = { it.getLong("c") },
        ) ?: 0L

        return FinancialSummary(
            baseCurrency = baseCurrency,
            today = todayIso,
            accounts = accounts,
            liquidSavings = liquidSavings,
            avgMonthlyIncome = avgMonthlyIncome,
            avgMonthlyExpense = avgMonthlyExpense,
            // `+(x).toFixed(2)`: web rounds the DIFFERENCE rather than
            // subtracting two already-rounded numbers, and the two disagree by
            // a paisa often enough to matter in a prompt.
            monthlySurplus = jsToFixed2Number(avgMonthlyIncome - avgMonthlyExpense),
            fixedMonthlyObligations = major(obligations.toDouble()),
            goals = goals,
            upcoming = upcoming,
            splits = SummarySplits(major(owed.toDouble()), major(owe.toDouble()), groupCount.toInt()),
            monthlyCashflow = monthlyCashflow,
            topCategories = topCategories,
        )
    }
}

/**
 * Web's `major()`: `Math.round(minor) / 100`.
 *
 * This is web bug #8's SIXTH site and it is reproduced, not fixed. Unlike the
 * parser sites, this number is not stored anywhere -- it goes into a prompt and
 * is read by a model. Fixing it here with `toMajor()` would make a JPY user's
 * phone send a different snapshot than their browser for the same ledger, and
 * the assistant would answer differently on each. Recorded against #8.
 */
private fun major(minor: Double): Double = jsRound(minor) / 100.0

/** `+(x).toFixed(2)` -- rounded to two decimals and back to a number. */
private fun jsToFixed2Number(x: Double): Double {
    val negative = x < 0
    val v = if (negative) -x else x
    val rounded = BigDecimal(v).setScale(2, RoundingMode.HALF_UP).toDouble()
    return if (negative) -rounded else rounded
}

/** Web's `["savings", "current", "cash"].includes(a.type)`. */
private val LIQUID_ACCOUNT_TYPES = setOf("savings", "current", "cash")

/** Web averages over three months of transactions. */
private const val AVERAGE_MONTHS = 3.0

/** Six calendar months of income vs expense, for the trend the model may chart. */
private const val CASHFLOW_MONTHS = 6

private const val TOP_CATEGORY_LIMIT = 8L

/** Web's spelling, which is NOT the analyzer's "Uncategorised". Both reproduced as-is. */
private const val UNCATEGORIZED_LABEL = "Uncategorized"

/** Web's `threshold_pct: 80` on an assistant-created budget. */
private const val BUDGET_DEFAULT_THRESHOLD_PCT = 80

// ---- wire format ----------------------------------------------------------

/** Domain's own JSON tree back out to kotlinx, for a tool call's `input`. */
private fun AssistantJson.toWire(): JsonElement = when (this) {
    is AssistantJson.Str -> JsonPrimitive(value)
    is AssistantJson.Num -> JsonPrimitive(value)
    is AssistantJson.Bool -> JsonPrimitive(value)
    is AssistantJson.Arr -> JsonArray(values.map { it.toWire() })
    is AssistantJson.Obj -> JsonObject(values.mapValues { (_, v) -> v.toWire() })
    AssistantJson.Null -> JsonNull
}

private fun JsonElement.toDomainJson(): AssistantJson = when (this) {
    is JsonNull -> AssistantJson.Null
    is JsonObject -> AssistantJson.Obj(mapValues { (_, v) -> v.toDomainJson() })
    is JsonArray -> AssistantJson.Arr(map { it.toDomainJson() })
    is JsonPrimitive -> when {
        isString -> AssistantJson.Str(content)
        booleanOrNull != null -> AssistantJson.Bool(booleanOrNull!!)
        doubleOrNull != null -> AssistantJson.Num(doubleOrNull!!)
        else -> AssistantJson.Null
    }
}

private fun AssistantContent.toWire(): JsonElement = when (this) {
    is AssistantContent.Text -> buildJsonObject {
        put("type", "text")
        put("text", text)
    }
    is AssistantContent.Use -> buildJsonObject {
        put("type", "tool_use")
        put("id", use.id)
        put("name", use.name)
        put("input", JsonObject(use.input.mapValues { (_, v) -> v.toWire() }))
    }
    is AssistantContent.Result -> buildJsonObject {
        put("type", "tool_result")
        put("tool_use_id", toolUseId)
        put("content", content)
    }
}

/**
 * One message as the API wants it.
 *
 * `content` is EITHER a bare string or an array of blocks, never both. Sending
 * an array where a string belongs is accepted; sending both is not, and mixing
 * them across a conversation is what makes a window fail to open on a user turn.
 */
private fun ApiMessage.toRequestJson(): JsonElement = buildJsonObject {
    put("role", role)
    val text = textContent
    if (text != null) put("content", text) else put("content", JsonArray(blocks.map { it.toWire() }))
}

/** A block the model sent back. Unknown types are dropped rather than guessed at. */
private fun JsonElement.toAssistantContent(): AssistantContent? {
    val o = this as? JsonObject ?: return null
    return when (o["type"]?.jsonPrimitive?.contentOrNull) {
        "text" -> AssistantContent.Text(o["text"]?.jsonPrimitive?.contentOrNull.orEmpty())
        "tool_use" -> AssistantContent.Use(
            ToolUse(
                id = o["id"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                name = o["name"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                input = (o["input"]?.toDomainJson() as? AssistantJson.Obj)?.values ?: emptyMap(),
            ),
        )
        "tool_result" -> AssistantContent.Result(
            toolUseId = o["tool_use_id"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            content = o["content"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        )
        else -> null
    }
}

