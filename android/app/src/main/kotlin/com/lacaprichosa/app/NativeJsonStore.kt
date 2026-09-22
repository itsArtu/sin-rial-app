package com.lacaprichosa.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object NativeJsonStore {
    class StaleStateException : IllegalStateException("State changed in another window")
    const val STORE_NAME = "la_caprichosa_native_010"
    private val arrayKeys = listOf("accounts", "movements", "debts", "budgets", "goals", "cards", "balanceAdjustments",
        "budgetPlans", "sharedSavings", "savingsCircles")
    private val objectKeys = listOf("savingsFunds")
    internal val partNames = arrayKeys + objectKeys
    internal var cipher = StateCipher()
    private val rateKeys = listOf("bcvRateSnapshots", "rateCheckedDate", "rateLastFetchAttemptMillis",
        "rate", "previousRate", "lastRateDate", "rateEffectiveDate", "rateUpdatedAt", "lastRateMillis",
        "eurRate", "previousEurRate", "eurRateEffectiveDate", "eurRateUpdatedAt", "eurLastRateMillis",
        "usdtRate", "previousUsdtRate", "usdtRateUpdatedAt", "usdtLastRateMillis",
        "rateLastAttemptMillis", "rateFetchStatus", "eurRateFetchStatus", "usdtRateFetchStatus")

    fun prefs(context: Context): SharedPreferences = context.getSharedPreferences(STORE_NAME, Context.MODE_PRIVATE)

    @Synchronized fun readState(context: Context, collections: Set<String> = partNames.toSet()): JSONObject = SqliteStateStore(context, cipher).use { store ->
        store.transaction { store.readState(collections) }
    }

    @Synchronized fun readMain(context: Context): JSONObject = SqliteStateStore(context, cipher).use { store ->
        store.transaction { store.readMain() }
    }

    @Synchronized fun readUiState(context: Context): Pair<String, Long> = SqliteStateStore(context, cipher).use { store ->
        store.transaction { store.readState().toString() to store.uiRevision() }
    }

    @Synchronized fun uiRevision(context: Context): Long = SqliteStateStore(context, cipher).use { store ->
        store.transaction { store.uiRevision() }
    }

    @Synchronized fun writeState(context: Context, rawState: String, expectedRevision: Long? = null): Long {
        val source = JSONObject(rawState)
        val parts = mutableMapOf<String, String>()
        for (key in arrayKeys) parts[key] = (if (source.has(key)) source.getJSONArray(key) else JSONArray()).toString()
        for (key in objectKeys) parts[key] = (if (source.has(key)) source.getJSONObject(key) else JSONObject()).toString()
        return writeSplitState(context, source.toString(), parts, expectedRevision)
    }

    @Synchronized fun writeSplitState(context: Context, rawMainState: String, rawParts: Map<String, String>,
                                    expectedRevision: Long? = null): Long {
        require(rawParts.keys.all { it in partNames }) { "Unknown state collection" }
        val slim = JSONObject(rawMainState)
        val parts = mutableMapOf<String, Any>()
        for (key in partNames) {
            val raw = rawParts[key]
            if (raw != null) parts[key] = if (key in arrayKeys) JSONArray(raw) else JSONObject(raw)
            else if (slim.has(key)) parts[key] = if (key in arrayKeys) slim.getJSONArray(key) else slim.getJSONObject(key)
            slim.remove(key)
        }
        return SqliteStateStore(context, cipher).use { store ->
            store.transaction {
                if (expectedRevision != null && expectedRevision != store.uiRevision()) throw StaleStateException()
                val stored = store.readMain()
                if (stored.optLong("rateLastAttemptMillis") > slim.optLong("rateLastAttemptMillis")) {
                    for (key in rateKeys) if (stored.has(key)) slim.put(key, stored.get(key))
                }
                // Native authentication owns these fields, never a stale Flutter snapshot.
                if (stored.optBoolean("nativeSecurityV1")) {
                    for (key in PinSecurity.fields) {
                        if (stored.has(key)) slim.put(key, stored.get(key)) else slim.remove(key)
                    }
                }
                store.write(slim, parts)
            }
        }
    }

    @Synchronized fun updateRateFields(context: Context, rates: JSONObject) {
        updateMain(context) { main ->
            if (rates.optLong("rateLastAttemptMillis") >= main.optLong("rateLastAttemptMillis")) {
                for (key in rateKeys) if (rates.has(key)) main.put(key, rates.get(key))
            }
        }
    }

    @Synchronized internal fun updateMain(context: Context, action: (JSONObject) -> Unit): JSONObject {
        return SqliteStateStore(context, cipher).use { store ->
            store.transaction {
                val state = store.readMain()
                action(state)
                store.writeMain(state)
                state
            }
        }
    }
}
