package com.lacaprichosa.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object NativeJsonStore {
    const val STORE_NAME = "la_caprichosa_native_010"

    private const val STATE_KEY = "state"
    private const val SPLIT_MARKER_KEY = "state_split_v1"
    private val arrayKeys = listOf("accounts", "movements", "debts", "budgets", "goals", "cards", "balanceAdjustments")
    private val objectKeys = listOf("savingsFunds")
    private val rateKeys = listOf("rate", "previousRate", "lastRateDate", "rateEffectiveDate", "rateUpdatedAt", "lastRateMillis",
        "eurRate", "previousEurRate", "eurRateEffectiveDate", "eurRateUpdatedAt", "eurLastRateMillis",
        "usdtRate", "previousUsdtRate", "usdtRateUpdatedAt", "usdtLastRateMillis",
        "rateLastAttemptMillis", "rateFetchStatus", "eurRateFetchStatus", "usdtRateFetchStatus")

    fun prefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)
    }

    fun readState(context: Context): JSONObject {
        val prefs = prefs(context)
        val state = parseObject(prefs.getString(STATE_KEY, "{}"))
        for (key in arrayKeys) {
            val raw = prefs.getString(partKey(key), null) ?: continue
            state.put(key, parseArray(raw))
        }
        for (key in objectKeys) {
            val raw = prefs.getString(partKey(key), null) ?: continue
            state.put(key, parseObject(raw))
        }
        return state
    }

    @Synchronized
    fun writeState(context: Context, rawState: String) {
        val source = parseObject(rawState)
        val slim = JSONObject(source.toString())
        preserveNewerRates(context, slim)
        val editor = prefs(context).edit()

        for (key in arrayKeys) {
            val value = source.optJSONArray(key) ?: JSONArray()
            editor.putString(partKey(key), value.toString())
            slim.remove(key)
        }
        for (key in objectKeys) {
            val value = source.optJSONObject(key) ?: JSONObject()
            editor.putString(partKey(key), value.toString())
            slim.remove(key)
        }

        editor
            .putString(STATE_KEY, slim.toString())
            .putBoolean(SPLIT_MARKER_KEY, true)
            .apply()
    }

    @Synchronized
    fun writeSplitState(context: Context, rawMainState: String, rawParts: Map<String, String>) {
        val prefs = prefs(context)
        val slim = parseObject(rawMainState)
        preserveNewerRates(context, slim)
        val editor = prefs.edit()

        for (key in arrayKeys) {
            slim.remove(key)
            val raw = rawParts[key]
            if (raw != null) {
                editor.putString(partKey(key), parseArray(raw).toString())
            } else if (!prefs.contains(partKey(key))) {
                parseObject(prefs.getString(STATE_KEY, "{}")).optJSONArray(key)?.let {
                    editor.putString(partKey(key), it.toString())
                }
            }
        }
        for (key in objectKeys) {
            slim.remove(key)
            val raw = rawParts[key]
            if (raw != null) {
                editor.putString(partKey(key), parseObject(raw).toString())
            } else if (!prefs.contains(partKey(key))) {
                parseObject(prefs.getString(STATE_KEY, "{}")).optJSONObject(key)?.let {
                    editor.putString(partKey(key), it.toString())
                }
            }
        }

        editor
            .putString(STATE_KEY, slim.toString())
            .putBoolean(SPLIT_MARKER_KEY, true)
            .apply()
    }

    private fun partKey(key: String) = "state_part_$key"

    @Synchronized
    fun updateRateFields(context: Context, rates: JSONObject) {
        val prefs = prefs(context)
        val main = parseObject(prefs.getString(STATE_KEY, "{}"))
        if (rates.optLong("rateLastAttemptMillis") < main.optLong("rateLastAttemptMillis")) return
        for (key in rateKeys) if (rates.has(key)) main.put(key, rates.get(key))
        prefs.edit().putString(STATE_KEY, main.toString()).apply()
    }

    private fun preserveNewerRates(context: Context, incoming: JSONObject) {
        val stored = parseObject(prefs(context).getString(STATE_KEY, "{}"))
        if (stored.optLong("rateLastAttemptMillis") <= incoming.optLong("rateLastAttemptMillis")) return
        for (key in rateKeys) if (stored.has(key)) incoming.put(key, stored.get(key))
    }

    private fun parseObject(raw: String?): JSONObject {
        if (raw.isNullOrBlank()) return JSONObject()
        return runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
    }

    private fun parseArray(raw: String?): JSONArray {
        if (raw.isNullOrBlank()) return JSONArray()
        return runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
    }
}
