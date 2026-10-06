package com.lacaprichosa.app

import org.json.JSONObject
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

internal data class RecurringReminder(val tag: String, val name: String, val kind: String,
                                     val dateKey: String, val due: Calendar) {
    fun isDue(now: Long) = DebtReminder.dayNumber(due) <=
        DebtReminder.dayNumber(Calendar.getInstance().apply { timeInMillis = now })
    val signature get() = "$kind:$name:$dateKey"
    val text get() = "$name: $kind por confirmar."

    companion object {
        const val TAG_PREFIX = "sin_rial_recurring:"
        fun fromState(state: JSONObject): List<RecurringReminder> {
            val rules = state.optJSONArray("recurringMovements") ?: return emptyList()
            val resolved = mutableMapOf<String, MutableSet<String>>()
            val movements = state.optJSONArray("movements")
            if (movements != null) for (i in 0 until movements.length()) {
                val movement = movements.optJSONObject(i) ?: continue
                val id = movement.optString("recurringId")
                if (id.isNotEmpty()) resolved.getOrPut(id) { mutableSetOf() }.add(movement.optString("recurringDate"))
            }
            val accounts = state.optJSONArray("accounts")
            val currencies = mutableMapOf<String, String>()
            if (accounts != null) for (i in 0 until accounts.length()) {
                val account = accounts.optJSONObject(i) ?: continue
                currencies[account.optString("id")] = account.optString("currency")
            }
            return (0 until rules.length()).mapNotNull { index ->
                val rule = rules.optJSONObject(index) ?: return@mapNotNull null
                val id = rule.optString("id")
                if (id.isEmpty() || rule.optBoolean("paused") || rule.optBoolean("archived") ||
                    !rule.optBoolean("notify", true) || rule.optString("type") !in setOf("income", "expense") ||
                    rule.optDouble("amount", 0.0).let { !it.isFinite() || it <= 0 } ||
                    currencies[rule.optString("accountId")] != rule.optString("currency")) return@mapNotNull null
                val handled = resolved[id]?.toMutableSet() ?: mutableSetOf()
                val skipped = rule.optJSONArray("skippedDates")
                if (skipped != null) for (i in 0 until skipped.length()) handled.add(skipped.optString(i))
                val due = nextDate(rule, handled) ?: return@mapNotNull null
                RecurringReminder(TAG_PREFIX + id, rule.optString("name"),
                    if (rule.optString("type") == "income") "ingreso" else "gasto", key(due), due)
            }
        }

        internal fun nextDate(rule: JSONObject, handled: Set<String>): Calendar? {
            val start = parse(rule.optString("startDate")) ?: return null
            val frequency = rule.optString("frequency")
            if (frequency !in setOf("weekly", "fortnightly", "monthly")) return null
            for (i in 0..handled.size) {
                // Always add from the original anchor, so Jan 31 -> Feb 28 -> Mar 31.
                val candidate = (start.clone() as Calendar).apply {
                    if (frequency == "monthly") add(Calendar.MONTH, i)
                    else add(Calendar.DAY_OF_YEAR, i * if (frequency == "weekly") 7 else 15)
                }
                if (key(candidate) !in handled) return candidate
            }
            return null
        }

        internal fun key(date: Calendar): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date.time)
        private fun parse(value: String): Calendar? {
            if (!Regex("\\d{4}-\\d{2}-\\d{2}").matches(value)) return null
            val parser = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }
            val position = ParsePosition(0)
            val date = parser.parse(value, position) ?: return null
            if (position.index != value.length) return null
            return Calendar.getInstance().apply { time = date }
        }
    }
}
