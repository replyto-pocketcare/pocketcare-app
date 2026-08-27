package com.sanvya.app.domain.assistant

import com.sanvya.app.domain.js.jsonNumber

/**
 * Validating and describing a tool call before it runs.
 *
 * Ported from `apps/web/src/assistant/tools.ts` — `isValidToolInput` and
 * `describeToolCall`. Executing a call is repository work and lives in the app;
 * deciding whether it is even worth showing, and what the confirm card says, is
 * not, and both have to read identically on every client.
 *
 * `describeToolCall`'s string is what the user reads before authorising a write
 * to their ledger. That makes it the single most consequential sentence in this
 * feature, and the reason it is here under vectors rather than formatted at each
 * call site.
 *
 * Mirrors iOS's AssistantToolCalls.swift.
 */

/** A tool call's arguments, as the model sent them. */
typealias ToolInput = Map<String, AssistantJson>

private fun ToolInput.string(key: String): String? =
    (this[key] as? AssistantJson.Str)?.value

/** `typeof v === "string" && v.trim().length > 0`. */
private fun ToolInput.nonBlank(key: String): Boolean = string(key)?.isNotBlank() == true

/** `typeof v === "number" && Number.isFinite(v) && v > 0`. */
private fun ToolInput.positive(key: String): Boolean {
    val n = (this[key] as? AssistantJson.Num)?.value ?: return false
    return n.isFinite() && n > 0
}

/**
 * Reject obviously-invalid or placeholder calls.
 *
 * Web's own comment names the case this exists for: the model firing
 * `record_transaction` with amount 0 for what was really a navigation request.
 * An invalid call is never shown as a confirm card at all — the model is told to
 * use a link instead — so this is the difference between a stray token and a
 * dialog asking the user to authorise a zero-rupee expense.
 *
 * An UNKNOWN name returns true, matching web's `default`. That is deliberate:
 * this function's job is catching nonsense arguments, not policing the tool
 * list, and the tool list is generated from one source anyway.
 */
fun isValidToolInput(name: String, input: ToolInput): Boolean = when (name) {
    "record_transaction" ->
        input.positive("amount") &&
            (input.string("type") == "expense" || input.string("type") == "income")
    "create_goal" -> input.nonBlank("name") && input.positive("target_amount")
    "reserve_to_goal" -> input.nonBlank("goal_name") && input.positive("amount")
    "create_budget" -> input.nonBlank("name") && input.positive("limit_amount")
    "create_subscription" -> input.nonBlank("name") && input.positive("amount")
    "create_group" -> input.nonBlank("name")
    else -> true
}

/**
 * How a value the model sent is spelled back to the user.
 *
 * Web interpolates the raw value into a template literal, so a number arrives
 * through JS's own number-to-string. `79900` reads as "79900" there and would
 * read as "79900.0" through a naive Kotlin `toString()`, on the one line in this
 * feature the user is asked to authorise.
 */
private fun ToolInput.text(key: String): String = when (val v = this[key]) {
    null, is AssistantJson.Null -> "undefined"
    is AssistantJson.Str -> v.value
    is AssistantJson.Bool -> v.value.toString()
    is AssistantJson.Num -> jsonNumber(v.value)
    is AssistantJson.Arr, is AssistantJson.Obj -> "[object]"
}

/** JS truthiness for the optional trailing clauses: absent, empty or 0 all drop the clause. */
private fun ToolInput.truthy(key: String): Boolean = when (val v = this[key]) {
    null, is AssistantJson.Null -> false
    is AssistantJson.Str -> v.value.isNotEmpty()
    is AssistantJson.Bool -> v.value
    is AssistantJson.Num -> v.value != 0.0 && !v.value.isNaN()
    is AssistantJson.Arr, is AssistantJson.Obj -> true
}

/**
 * One line describing a proposed action, for the confirm card.
 *
 * The curly quotes and the middle dots are web's, character for character. They
 * are not decoration: this is the string the two apps and the browser must all
 * show for the same call, and "Create goal "X"" versus "Create goal “X”" is a
 * visible difference on the one screen where trust is being asked for.
 */
fun describeToolCall(name: String, input: ToolInput, baseCurrency: String): String {
    val cur = input.string("currency")?.takeIf { it.isNotEmpty() } ?: baseCurrency
    return when (name) {
        "create_goal" -> {
            val by = if (input.truthy("by_date")) " by ${input.text("by_date")}" else ""
            "Create goal “${input.text("name")}” — target $cur ${input.text("target_amount")}$by"
        }
        "reserve_to_goal" ->
            "Reserve $cur ${input.text("amount")} toward “${input.text("goal_name")}”"
        "create_budget" ->
            "Create ${input.text("period")} budget “${input.text("name")}” — limit $cur ${input.text("limit_amount")}"
        "record_transaction" -> {
            val desc = if (input.truthy("description")) " — ${input.text("description")}" else ""
            val acct = if (input.truthy("account")) " (${input.text("account")})" else ""
            "Record ${input.text("type")} of $cur ${input.text("amount")}$desc$acct"
        }
        "create_subscription" ->
            // `String(input.billing_cycle).replace("ly", "")` -- a STRING
            // pattern, so JS replaces only the FIRST occurrence. "monthly"
            // becomes "month" either way; the distinction is copied because the
            // day a cycle contains a second "ly" the two must still agree.
            "Add subscription “${input.text("name")}” — $cur ${input.text("amount")}/" +
                input.text("billing_cycle").replaceFirst("ly", "")
        "create_group" -> {
            val dates = if (input.truthy("start_date")) {
                val end = if (input.truthy("end_date")) "–${input.text("end_date")}" else ""
                " · ${input.text("start_date")}$end"
            } else {
                ""
            }
            val auto = if (input.truthy("auto_split")) " · auto-split" else ""
            "Create ${input.text("kind")} “${input.text("name")}”$dates$auto"
        }
        "remember" -> "Remembered: ${input.text("fact")}"
        else -> "Run $name"
    }
}
