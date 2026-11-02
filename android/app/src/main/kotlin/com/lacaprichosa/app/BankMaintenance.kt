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
    const val POLICY = "ves-bank-close-2026-11"
    private const val LEGACY_POLICY = "ves-current-2026-09"
    private val AMOUNT = BigDecimal("684.00")
    private val ZONE = TimeZone.getTimeZone("America/Caracas")

    private fun monthFormat(zone: TimeZone) = SimpleDateFormat("yyyy-MM", Locale.US).apply { timeZone = zone }

    // Keep the existing first-of-month cycle IDs, moving 31-day charges one day earlier.
    private fun latestCycle(now: Long, zone: TimeZone): String {
        val date = Calendar.getInstance(zone).apply { timeInMillis = now }
        if (date.get(Calendar.DAY_OF_MONTH) == 31) {
            date.set(Calendar.DAY_OF_MONTH, 1)
            date.add(Calendar.MONTH, 1)
        }
        return monthFormat(zone).format(date.time)
    }

    private fun cycleStart(cycle: String, zone: TimeZone) = Calendar.getInstance(zone).apply {
        clear()
        set(cycle.substring(0, 4).toInt(), cycle.substring(5, 7).toInt() - 1, 1)
    }

    private fun nextCycle(cycle: String, zone: TimeZone): String = monthFormat(zone).format(
        cycleStart(cycle, zone).apply { add(Calendar.MONTH, 1) }.time
    )

    fun eligible(account: JSONObject): Boolean = account.optString("kind") == "national" &&
        Regex("\\d{4}").matches(account.optString("provider")) &&
        account.optString("bankAccountType") in setOf("current", "savings") &&
        account.optString("currency") == "VES"

    fun hasEnabled(state: JSONObject): Boolean {
        val accounts = state.optJSONArray("accounts") ?: return false
        return (0 until accounts.length()).any { accounts.optJSONObject(it)?.let(::eligible) == true }
    }

    fun apply(context: Context, now: Long = System.currentTimeMillis()): Boolean = synchronized(NativeJsonStore) {
        val state = NativeJsonStore.readState(context, setOf("accounts"))
        if (!hasEnabled(state)) return false
        val month = latestCycle(now, ZONE)
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
    internal fun applyToState(state: JSONObject, now: Long, zone: TimeZone = ZONE): Boolean {
        val accounts = state.optJSONArray("accounts") ?: return false
        val movements = state.optJSONArray("movements") ?: JSONArray().also { state.put("movements", it) }
        val month = latestCycle(now, zone)
        val next = nextCycle(month, zone)
        val first = cycleStart(month, zone)
        val closingDay = (first.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -1) }
        val chargeDay = if (closingDay.get(Calendar.DAY_OF_MONTH) == 31) closingDay else first
        val date = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply { timeZone = zone }.format(chargeDay.time)
        val period = monthFormat(zone).format(closingDay.time)
        val monthName = SimpleDateFormat("MMMM", Locale.forLanguageTag("es-VE")).apply { timeZone = zone }.format(closingDay.time)
        var changed = false
        val ids = (0 until movements.length()).mapNotNull { movements.optJSONObject(it)?.optString("id") }.toSet()
        for (index in 0 until accounts.length()) {
            val account = accounts.optJSONObject(index) ?: continue
            if (!eligible(account)) continue
            val due = account.optString("maintenanceNextMonth")
            // Preserve existing cursors across the policy upgrade; new accounts start at the next close.
            if (account.optString("maintenancePolicy") !in setOf(POLICY, LEGACY_POLICY) ||
                !Regex("\\d{4}-(0[1-9]|1[0-2])").matches(due)) {
                account.put("maintenancePolicy", POLICY)
                account.put("maintenanceEnabled", true)
                account.put("maintenanceAmount", AMOUNT.toDouble())
                account.put("maintenanceNextMonth", next)
                changed = true
                continue
            }
            if (account.optString("maintenancePolicy") != POLICY) {
                account.put("maintenancePolicy", POLICY)
                account.put("maintenanceEnabled", true)
                account.put("maintenanceAmount", AMOUNT.toDouble())
                changed = true
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
                    put("description", "Comisión mantenimiento mensual $monthName")
                    put("category", "Comisiones bancarias"); put("maintenanceMonth", month)
                    put("maintenancePeriod", period)
                    put("maintenanceAccountId", id); put("reference", "")
                })
                account.put("balance", balance.subtract(amount).setScale(2, RoundingMode.DOWN).toDouble())
            }
            // If Android missed prior months, register only this month, never retroactive charges.
            account.put("maintenanceNextMonth", next)
            changed = true
        }
        return changed
    }
}
