package com.sanvya.app.domain.money

import com.sanvya.app.domain.vectors.FunctionRegistry
import com.sanvya.app.domain.vectors.jsonNumber
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

// P1.1a: wires the real Money.kt port into FunctionRegistry so
// money.json's vectors un-skip. Registered under (domain="money",
// fn=<name>) to match tools/golden-vectors/vectors/money.json exactly --
// field names below (a/b, money, items, total, to/rate, etc.) were read
// directly off tools/golden-vectors/export.ts's money section, not
// guessed. Called from VectorRunnerTest.money() (kotlin.test).
//
// format() is deliberately NOT registered here -- see Money.kt's header
// comment for why (locale table + cross-platform ICU string exactness
// needs its own careful, build-verified pass). money.json's 3 "format"
// vectors stay skipped until that follow-up task.

private const val DOMAIN = "money"

private fun JsonElement.asMoney(): Money {
    val obj = jsonObject
    return Money(obj.getValue("amount").jsonPrimitive.long, obj.getValue("currency").jsonPrimitive.content)
}

private fun Money.toJson(): JsonElement = JsonObject(
    mapOf(
        "amount" to JsonPrimitive(amount.toString()),
        "currency" to JsonPrimitive(currency),
    )
)

private fun List<Money>.toJsonArr(): JsonElement = JsonArray(map { it.toJson() })

fun registerMoneyVectors() {
    FunctionRegistry.register(DOMAIN, "minorUnits") { input ->
        val currency = input.jsonObject.getValue("currency").jsonPrimitive.content
        JsonPrimitive(minorUnits(currency))
    }

    FunctionRegistry.register(DOMAIN, "money") { input ->
        val obj = input.jsonObject
        val amount = obj.getValue("amount").jsonPrimitive.double
        val currency = obj.getValue("currency").jsonPrimitive.content
        money(amount, currency).toJson()
    }

    FunctionRegistry.register(DOMAIN, "fromMajor") { input ->
        val obj = input.jsonObject
        val value = obj.getValue("value").jsonPrimitive.double
        val currency = obj.getValue("currency").jsonPrimitive.content
        fromMajor(value, currency).toJson()
    }

    FunctionRegistry.register(DOMAIN, "toMajor") { input ->
        val m = input.jsonObject.getValue("money").asMoney()
        jsonNumber(toMajor(m))
    }

    FunctionRegistry.register(DOMAIN, "isZero") { input ->
        val m = input.jsonObject.getValue("money").asMoney()
        JsonPrimitive(isZero(m))
    }

    FunctionRegistry.register(DOMAIN, "isNegative") { input ->
        val m = input.jsonObject.getValue("money").asMoney()
        JsonPrimitive(isNegative(m))
    }

    FunctionRegistry.register(DOMAIN, "add") { input ->
        val obj = input.jsonObject
        add(obj.getValue("a").asMoney(), obj.getValue("b").asMoney()).toJson()
    }

    FunctionRegistry.register(DOMAIN, "subtract") { input ->
        val obj = input.jsonObject
        subtract(obj.getValue("a").asMoney(), obj.getValue("b").asMoney()).toJson()
    }

    FunctionRegistry.register(DOMAIN, "negate") { input ->
        negate(input.jsonObject.getValue("money").asMoney()).toJson()
    }

    FunctionRegistry.register(DOMAIN, "scale") { input ->
        val obj = input.jsonObject
        val m = obj.getValue("money").asMoney()
        val factor = obj.getValue("factor").jsonPrimitive.double
        scale(m, factor).toJson()
    }

    FunctionRegistry.register(DOMAIN, "sum") { input ->
        val obj = input.jsonObject
        val items = obj.getValue("items").jsonArray.map { it.asMoney() }
        // "currency" is explicit JSON null in the empty-list-throws vector
        // (export.ts writes `currency: null` literally, not `undefined`,
        // which JSON.stringify would have dropped instead of nulling).
        val currencyElement = obj["currency"]
        val currency = if (currencyElement == null || currencyElement is JsonNull) {
            null
        } else {
            currencyElement.jsonPrimitive.content
        }
        sum(items, currency).toJson()
    }

    FunctionRegistry.register(DOMAIN, "convert") { input ->
        val obj = input.jsonObject
        val m = obj.getValue("money").asMoney()
        val to = obj.getValue("to").jsonPrimitive.content
        val rate = obj.getValue("rate").jsonPrimitive.double
        convert(m, to, rate).toJson()
    }

    FunctionRegistry.register(DOMAIN, "split") { input ->
        val obj = input.jsonObject
        val total = obj.getValue("total").asMoney()
        val parts = obj.getValue("parts").jsonPrimitive.long.toInt()
        split(total, parts).toJsonArr()
    }

    FunctionRegistry.register(DOMAIN, "itemsReconcile") { input ->
        val obj = input.jsonObject
        val total = obj.getValue("total").asMoney()
        val items = obj.getValue("items").jsonArray.map { it.asMoney() }
        JsonPrimitive(itemsReconcile(total, items))
    }
}
