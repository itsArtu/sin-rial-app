package com.lacaprichosa.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

object BankMaintenance {
    const val POLICY = "ves-current-2026-09"
    private val AMOUNT = BigDecimal("684.00")

    fun eligible(account: JSONObject): Boolean = account.optString("kind") == "national" &&
        Regex("\\d{4}").matches(account.optString("provider")) &&
        account.optString("bankAccountType") == "current" &&
        account.optString("currency") == "VES"

    fun hasEnabled(state: JSONObject): Boolean {
        val accounts = state.optJSONArray("accounts") ?: return false
        return (0 until accounts.length()).any { accounts.optJSONObject(it)?.let(::eligible) == true }
    }

    fun apply(context: Context, now: Long = System.currentTimeMillis()): Boolean = synchronized(NativeJsonStore) {
        val state = NativeJsonStore.readState(context, setOf("accounts"))
        if (!hasEnabled(state)) return false
        val month = SimpleDateFormat("yyyy-MM", Locale.US).format(java.util.Date(now))
        val accounts = state.getJSONArray("accounts")
        if (!(0 until accounts.length()).any { index -> accounts.optJSONObject(index)?.let {
                eligible(it) && (it.optString("maintenancePolicy") != POLICY ||
                    it.optString("maintenanceNextMonth").let { due -> due.isEmpty() || due <= month })
            } == true }) return false
        state.put("movements", NativeJsonStore.readState(context, setOf("movements")).getJSONArray("movements"))
        if (!applyToState(state, now)) return false
        NativeJsonStore.writeSplitState(context, state.toString(), emptyMap(), NativeJsonStore.uiRevision(context))
        true
    }

    // Account cursor and ledger entry commit together. Deleting an entry never schedules it again.
    internal fun applyToState(state: JSONObject, now: Long, zone: TimeZone = TimeZone.getDefault()): Boolean {
        val accounts = state.optJSONArray("accounts") ?: return false
        val movements = state.optJSONArray("movements") ?: JSONArray().also { state.put("movements", it) }
        val current = Calendar.getInstance(zone).apply { timeInMillis = now }
        val monthFormat = SimpleDateFormat("yyyy-MM", Locale.US).apply { timeZone = zone }
        val month = monthFormat.format(current.time)
        val next = (current.clone() as Calendar).apply { set(Calendar.DAY_OF_MONTH, 1); add(Calendar.MONTH, 1) }
        val first = (current.clone() as Calendar).apply {
            set(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val date = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply { timeZone = zone }.format(first.time)
        var changed = false
        val ids = (0 until movements.length()).mapNotNull { movements.optJSONObject(it)?.optString("id") }.toSet()
        for (index in 0 until accounts.length()) {
            val account = accounts.optJSONObject(index) ?: continue
            if (!eligible(account)) continue
            val due = account.optString("maintenanceNextMonth")
            // Existing accounts opt into the new policy starting next month, never retroactively.
            if (account.optString("maintenancePolicy") != POLICY ||
                !Regex("\\d{4}-(0[1-9]|1[0-2])").matches(due)) {
                account.put("maintenancePolicy", POLICY)
                account.put("maintenanceEnabled", true)
                account.put("maintenanceAmount", AMOUNT.toDouble())
                account.put("maintenanceNextMonth", monthFormat.format(next.time))
                changed = true
                continue
            }
            if (due > month) continue
            val id = account.optString("id").takeIf { it.isNotBlank() } ?: continue
            val amount = AMOUNT
            val balance = runCatching { BigDecimal(account.optString("balance", "0")) }.getOrNull() ?: continue
            val movementId = "maintenance:$id:$month"
            if (movementId !in ids) {
                val currency = account.getString("currency")
                movements.put(JSONObject().apply {
                    put("id", movementId); put("type", "expense"); put("accountId", id)
                    put("amount", amount.toDouble()); put("currency", currency); put("feeAmount", 0)
                    put("feeCurrency", currency); put("feeMode", "none"); put("date", date)
                    put("description", "Mantenimiento mensual - ${account.optString("name", "Banco")}")
                    put("category", "Comisiones bancarias"); put("maintenanceMonth", month)
                    put("maintenanceAccountId", id); put("reference", "")
                })
                account.put("balance", balance.subtract(amount).setScale(2, RoundingMode.HALF_UP).toDouble())
            }
            // If Android missed prior months, register only this month, never retroactive charges.
            account.put("maintenanceNextMonth", monthFormat.format(next.time))
            changed = true
        }
        return changed
    }
}
