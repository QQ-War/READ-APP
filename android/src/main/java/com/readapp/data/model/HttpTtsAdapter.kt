package com.readapp.data.model

import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import java.lang.reflect.Type

class HttpTtsAdapter : JsonDeserializer<HttpTTS> {
    override fun deserialize(json: JsonElement, typeOfT: Type, context: JsonDeserializationContext): HttpTTS {
        val obj = json.asJsonObject
        val id = readAsString(obj, "id")
        val name = readAsString(obj, "name")
        val url = readAsString(obj, "url")
        val userid = readAsString(obj, "userid")
        val contentType = readAsString(obj, "contentType")
        val concurrentRate = readAsString(obj, "concurrentRate")
        val loginUrl = readAsString(obj, "loginUrl")
        val loginUi = readAsString(obj, "loginUi")
        val header = readAsString(obj, "header")
        val enabledCookieJar = readAsBoolean(obj, "enabledCookieJar")
        val loginCheckJs = readAsString(obj, "loginCheckJs")
        val lastUpdateTime = readAsLong(obj, "lastUpdateTime")
        return HttpTTS(
            id = id,
            userid = userid,
            name = name,
            url = url,
            contentType = contentType,
            concurrentRate = concurrentRate,
            loginUrl = loginUrl,
            loginUi = loginUi,
            header = header,
            enabledCookieJar = enabledCookieJar,
            loginCheckJs = loginCheckJs,
            lastUpdateTime = lastUpdateTime
        )
    }

    private fun readAsString(obj: JsonObject, key: String): String {
        val el = obj.get(key) ?: return ""
        return when {
            el.isJsonNull -> ""
            el.isJsonPrimitive && el.asJsonPrimitive.isNumber -> el.asJsonPrimitive.asNumber.toLong().toString()
            else -> runCatching { el.asString }.getOrDefault("")
        }
    }

    private fun readAsLong(obj: JsonObject, key: String): Long? {
        val el = obj.get(key) ?: return null
        if (el.isJsonNull) return null
        return runCatching { el.asLong }.getOrNull()
    }

    private fun readAsBoolean(obj: JsonObject, key: String): Boolean? {
        val el = obj.get(key) ?: return null
        if (el.isJsonNull) return null
        return when {
            el.isJsonPrimitive && el.asJsonPrimitive.isBoolean -> el.asBoolean
            el.isJsonPrimitive && el.asJsonPrimitive.isNumber -> el.asNumber.toInt() != 0
            else -> {
                val raw = runCatching { el.asString }.getOrNull() ?: return null
                raw.equals("true", true) || raw == "1"
            }
        }
    }
}
