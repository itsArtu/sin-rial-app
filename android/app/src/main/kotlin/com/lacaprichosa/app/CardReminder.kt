package com.lacaprichosa.app

import org.json.JSONObject
import java.util.Calendar

internal object CardReminder {
    const val ID = 2400
    const val SENT_KEY = "card_reminder_sent_v1"
    data class Notice(val signature: String, val text: String)

    fun enabled(state: JSONObject): Boolean = state.optBoolean("creditRemindersEnabled", true) &&
        state.optJSONArray("accounts")?.let { cards -> (0 until cards.length()).any {
            cards.optJSONObject(it)?.let { card -> card.optString("kind") == "credit" && card.optDouble("balance", 0.0) < -0.005 } == true
        } } == true

    fun notice(state: JSONObject, now: Long = System.currentTimeMillis()): Notice? {
        if (!enabled(state)) return null
        val today = Calendar.getInstance().apply { timeInMillis = now }
        val day = DebtReminder.dayNumber(today)
        val cards = state.optJSONArray("accounts") ?: return null
        val events = mutableListOf<Pair<String, String>>()
        for (i in 0 until cards.length()) {
            val card = cards.optJSONObject(i) ?: continue
            val balance = card.optDouble("balance", 0.0)
            if (card.optString("kind") != "credit" || !balance.isFinite() || balance >= -0.005) continue
            val name = card.optString("label").ifBlank { card.optString("name", "Tu tarjeta") }.take(38)
            for ((field, lead) in listOf("dueDay" to 3, "cutDay" to 1)) {
                val configured = card.optInt(field, 0)
                if (configured !in 1..31) continue
                for (offset in -1..1) {
                    val date = (today.clone() as Calendar).apply {
                        set(Calendar.DAY_OF_MONTH, 1); add(Calendar.MONTH, offset)
                        set(Calendar.DAY_OF_MONTH, configured.coerceAtMost(getActualMaximum(Calendar.DAY_OF_MONTH)))
                    }
                    val remaining = DebtReminder.dayNumber(date) - day
                    if (remaining !in 0..lead) continue
                    val whenText = when (remaining) { 0L -> "hoy"; 1L -> "ma\u00f1ana"; else -> "en $remaining d\u00edas" }
                    val event = if (field == "dueDay") "pago" else "corte"
                    events.add("${card.optString("id")}:$field:${DebtReminder.dayNumber(date)}:$remaining" to "$name: $event $whenText")
                }
            }
        }
        if (events.isEmpty()) return null
        events.sortBy { it.first }
        return Notice(events.joinToString("|") { it.first }, events.take(3).joinToString(". ") { it.second } +
            if (events.size > 3) ". Y ${events.size - 3} m\u00e1s." else ".")
    }
}
