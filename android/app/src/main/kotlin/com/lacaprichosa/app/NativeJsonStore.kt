package com.lacaprichosa.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object NativeJsonStore {
    const val STORE_NAME = "la_caprichosa_native_010"

    private const val STATE_KEY = "state"
    private const val SPLIT_MARKER_KEY = "state_split_v1"
    private val arrayKeys = listOf("accounts", "movements", "debts", "budgets", "goals", "cards")
    private val objectKeys = listOf("savingsFunds")

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

    fun writeState(context: Context, rawState: String) {
        val source = parseObject(rawState)
        val slim = JSONObject(source.toString())
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

    fun writeSplitState(context: Context, rawMainState: String, rawParts: Map<String, String>) {
        val prefs = prefs(context)
        val slim = parseObject(rawMainState)
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

    private fun parseObject(raw: String?): JSONObject {
        if (raw.isNullOrBlank()) return JSONObject()
        return runCatching { JSONObject(raw) }.getOrElse { JSONObject() }
    }

    private fun parseArray(raw: String?): JSONArray {
        if (raw.isNullOrBlank()) return JSONArray()
        return runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
    }
}
