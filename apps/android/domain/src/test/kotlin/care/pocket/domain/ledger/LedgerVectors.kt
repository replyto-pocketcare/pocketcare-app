package care.pocket.domain.ledger

import care.pocket.domain.money.Money
import care.pocket.domain.vectors.FunctionRegistry
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.2a: wires the real Ledger.kt port into FunctionRegistry so
// ledger.json's vectors un-skip. Registered under (domain="ledger",
// fn=<name>) to match tools/golden-vectors/vectors/ledger.json exactly --
// field names below (entry/accountId, account_id/to_account_id/to_amount
// on the entry itself, balances/base/rates/includeBlocked) were read
// directly off tools/golden-vectors/export.ts's ledger section, not
// guessed. Called from VectorRunnerTest.ledger() (kotlin.test).

private const val DOMAIN = "ledger"

private fun JsonElement.asMoney(): Money {
    val obj = jsonObject
    return Money(obj.getValue("amount").jsonPrimitive.long, obj.getValue("currency").jsonPrimitive.content)
}

private fun Money.toJson(): JsonElement = JsonObject(
    mapOf("amount" to JsonPrimitive(amount.toString()), "currency" to JsonPrimitive(currency))
)

private fun JsonElement.asLedgerEntry(): LedgerEntry {
    val obj = jsonObject
    return LedgerEntry(
        type = obj.getValue("type").jsonPrimitive.content,
        accountId = obj.getValue("account_id").jsonPrimitive.content,
        amount = obj.getValue("amount").jsonPrimitive.long,
        toAccountId = obj["to_account_id"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.content,
        toAmount = obj["to_amount"]?.takeIf { it !is JsonNull }?.jsonPrimitive?.long,
    )
}

fun registerLedgerVectors() {
    FunctionRegistry.register(DOMAIN, "signedEffectFor") { input ->
        val obj = input.jsonObject
        val entry = obj.getValue("entry").asLedgerEntry()
        val accountId = obj.getValue("accountId").jsonPrimitive.content
        // Stringified (like a Money amount), not a raw number -- the
        // exporter treats any raw minor-unit integer as money-shaped and
        // wraps it with amt() (see export.ts's header comment).
        JsonPrimitive(signedEffectFor(entry, accountId).toString())
    }

    FunctionRegistry.register(DOMAIN, "deriveBalance") { input ->
        val obj = input.jsonObject
        val accountId = obj.getValue("accountId").jsonPrimitive.content
        val currency = obj.getValue("currency").jsonPrimitive.content
        val entries = obj.getValue("entries").jsonArray.map { it.asLedgerEntry() }
        deriveBalance(accountId, currency, entries).toJson()
    }

    FunctionRegistry.register(DOMAIN, "availableBalance") { input ->
        val obj = input.jsonObject
        availableBalance(obj.getValue("total").asMoney(), obj.getValue("blocked").asMoney()).toJson()
    }

    FunctionRegistry.register(DOMAIN, "aggregateNetWorth") { input ->
        val obj = input.jsonObject
        val balances = obj.getValue("balances").jsonArray.map { b ->
            val bo = b.jsonObject
            AccountBalance(bo.getValue("balance").asMoney(), bo.getValue("blocked").asMoney())
        }
        val base = obj.getValue("base").jsonPrimitive.content
        val rates = obj.getValue("rates").jsonObject.mapValues { it.value.jsonPrimitive.double }
        val includeBlocked = obj.getValue("includeBlocked").jsonPrimitive.boolean
        // Mirrors the TS vector's own getRate closure exactly: same
        // currency short-circuits to 1, otherwise look up `rates` and
        // default to 1 if the pair isn't present.
        val getRate: RateLookup = { from, to -> if (from == to) 1.0 else rates[from] ?: 1.0 }
        aggregateNetWorth(balances, base, getRate, includeBlocked).toJson()
    }
}
