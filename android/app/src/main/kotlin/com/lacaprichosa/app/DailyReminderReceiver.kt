package com.lacaprichosa.app

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import org.json.JSONObject
import java.util.Calendar

class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        // Ledger maintenance does not depend on notification permission.
        runCatching { BankMaintenance.apply(context) }
        DailyReminderScheduler.schedule(context, force = true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (!manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(DailyReminderScheduler.CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE
        ) return
        val launchIntent = (context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context, ReminderNotifications.MOVEMENT_ID, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Serialize the last eligibility check and delivery with writes from either app window.
        synchronized(NativeJsonStore) {
            val state = runCatching { ReminderNotifications.readState(context) }.getOrNull() ?: return
            val now = System.currentTimeMillis()
            val day = DebtReminder.dayNumber(Calendar.getInstance().apply { timeInMillis = now })
            val enabled = state.optBoolean("dailyMovementReminderEnabled", true)
            val debts = ReminderNotifications.debts(state)
            ReminderNotifications.reconcile(context, debts, enabled, now)
            val prefs = NativeJsonStore.prefs(context)
            val edit = prefs.edit()
            val birthdayYear = BirthdayReminder.dueYear(state, now)
            if (birthdayYear != null && prefs.getInt("birthday_sent_year", 0) != birthdayYear) {
                manager.notify(BirthdayReminder.ID,
                    notification(context, "\u00a1Feliz cumplea\u00f1os!", "Sin Rial te desea un gran d\u00eda y un nuevo a\u00f1o lleno de metas cumplidas.", contentIntent))
                edit.putInt("birthday_sent_year", birthdayYear)
            }
            if (enabled && prefs.getLong("movement_reminder_sent_day", Long.MIN_VALUE) != day) {
                manager.notify(ReminderNotifications.MOVEMENT_ID,
                    notification(context, "Sin Rial", "Registra tus movimientos de hoy.", contentIntent))
                edit.putLong("movement_reminder_sent_day", day)
            }
            val sent = runCatching { JSONObject(prefs.getString(ReminderNotifications.SENT_KEY, "{}")!!) }.getOrDefault(JSONObject())
            for (debt in debts) {
                if (!debt.isDue(now)) continue
                val signature = debt.signature(now)
                val delivery = "$day:$signature"
                if (sent.optString(debt.tag) == delivery) continue
                manager.notify(debt.tag, ReminderNotifications.DEBT_ID,
                    notification(context, "Sin Rial: ${debt.kind} pendiente", debt.text(now), contentIntent, signature))
                sent.put(debt.tag, delivery)
            }
            edit.putString(ReminderNotifications.SENT_KEY, sent.toString()).apply()
            val recurring = RecurringReminder.fromState(state)
            ReminderNotifications.reconcileRecurring(context, recurring, now)
            val recurringSent = runCatching { JSONObject(prefs.getString(ReminderNotifications.RECURRING_SENT_KEY, "{}")!!) }.getOrDefault(JSONObject())
            for (reminder in recurring) {
                if (!reminder.isDue(now)) continue
                val delivery = "$day:${reminder.signature}"
                if (recurringSent.optString(reminder.tag) == delivery) continue
                manager.notify(reminder.tag, ReminderNotifications.RECURRING_ID,
                    notification(context, "Sin Rial: movimiento recurrente", reminder.text, contentIntent, reminder.signature))
                recurringSent.put(reminder.tag, delivery)
            }
            prefs.edit().putString(ReminderNotifications.RECURRING_SENT_KEY, recurringSent.toString()).apply()
        }
    }

    private fun notification(context: Context, title: String, text: String, contentIntent: PendingIntent, signature: String = ""): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, DailyReminderScheduler.CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        return builder.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title).setContentText(text).setContentIntent(contentIntent)
            .setExtras(Bundle().apply { putString(ReminderNotifications.SIGNATURE, signature) })
            .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true).build()
    }
}
