package com.lacaprichosa.app

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import org.json.JSONObject

internal object ReminderNotifications {
    const val DEBT_ID = 2200
    const val MOVEMENT_ID = 1901
    const val SIGNATURE = "sin_rial_reminder_signature"
    const val SENT_KEY = "debt_reminders_sent_v1"
    const val RECURRING_ID = 2300
    const val RECURRING_SENT_KEY = "recurring_reminders_sent_v1"

    fun readState(context: Context): JSONObject {
        val state = NativeJsonStore.readState(context, setOf("debts"))
        val rules = state.optJSONArray("recurringMovements")
        if (rules != null && (0 until rules.length()).any { index ->
                rules.optJSONObject(index)?.let { !it.optBoolean("archived") && !it.optBoolean("paused") && it.optBoolean("notify", true) } == true
            }) {
            val related = NativeJsonStore.readState(context, setOf("accounts", "movements"))
            state.put("accounts", related.getJSONArray("accounts"))
            state.put("movements", related.getJSONArray("movements"))
        }
        return state
    }

    fun reconcileRecurring(context: Context, reminders: List<RecurringReminder>, now: Long = System.currentTimeMillis()) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val byTag = reminders.associateBy { it.tag }
        for (active in manager.activeNotifications) {
            if (active.tag?.startsWith(RecurringReminder.TAG_PREFIX) != true) continue
            val reminder = byTag[active.tag]
            if (reminder == null || !reminder.isDue(now) ||
                active.notification.extras.getString(SIGNATURE) != reminder.signature) manager.cancel(active.tag, active.id)
        }
        val prefs = NativeJsonStore.prefs(context)
        val sent = runCatching { JSONObject(prefs.getString(RECURRING_SENT_KEY, "{}")!!) }.getOrDefault(JSONObject())
        val obsolete = sent.keys().asSequence().filter { it !in byTag }.toList()
        if (obsolete.isNotEmpty()) {
            obsolete.forEach { sent.remove(it) }
            prefs.edit().putString(RECURRING_SENT_KEY, sent.toString()).apply()
        }
    }

    fun debts(state: JSONObject): List<DebtReminder> {
        val debts = state.optJSONArray("debts") ?: return emptyList()
        return (0 until debts.length()).mapNotNull { index -> debts.optJSONObject(index)?.let(DebtReminder::from) }
    }

    fun reconcile(context: Context, debts: List<DebtReminder>, movementsEnabled: Boolean, now: Long = System.currentTimeMillis()) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val byTag = debts.associateBy { it.tag }
        for (active in manager.activeNotifications) {
            val tag = active.tag
            val oldDebt = tag == null && active.id >= DEBT_ID &&
                active.notification.extras.getString(Notification.EXTRA_TITLE).orEmpty().startsWith("Sin Rial: ")
            if (oldDebt || (active.id == MOVEMENT_ID && !movementsEnabled)) {
                manager.cancel(tag, active.id)
            } else if (tag?.startsWith(DebtReminder.TAG_PREFIX) == true) {
                val debt = byTag[tag]
                if (debt == null || !debt.isDue(now) || active.notification.extras.getString(SIGNATURE) != debt.signature(now)) {
                    manager.cancel(tag, active.id)
                }
            }
        }
        val prefs = NativeJsonStore.prefs(context)
        val sent = runCatching { JSONObject(prefs.getString(SENT_KEY, "{}")!!) }.getOrDefault(JSONObject())
        val obsolete = sent.keys().asSequence().filter { it !in byTag }.toList()
        if (obsolete.isNotEmpty()) {
            obsolete.forEach { sent.remove(it) }
            prefs.edit().putString(SENT_KEY, sent.toString()).apply()
        }
    }
}
