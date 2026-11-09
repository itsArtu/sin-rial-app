package com.lacaprichosa.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar
import java.util.TimeZone

object DailyReminderScheduler {
    const val CHANNEL_ID = "sin_rial_daily_movements"
    private const val REQUEST_CODE = 1900
    private const val SCHEDULE_KEY = "daily_reminder_schedule_v2"

    fun schedule(context: Context, force: Boolean = false) {
        val state = runCatching { NativeJsonStore.readMain(context) }.getOrNull() ?: return
        val enabled = state.optBoolean("dailyMovementReminderEnabled", true)
        val hour = state.optInt("dailyReminderHour", 19).coerceIn(0, 23)
        val minute = state.optInt("dailyReminderMinute", 0).coerceIn(0, 59)
        schedule(context, enabled, hour, minute, force)
    }

    fun schedule(context: Context, enabled: Boolean, hour: Int, minute: Int, force: Boolean = false) {
        createChannel(context)
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, DailyReminderReceiver::class.java)
        val existing = PendingIntent.getBroadcast(
            context, REQUEST_CODE, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        val prefs = NativeJsonStore.prefs(context)
        // Debt due-date notices share this daily wake-up, even with the movement reminder off.
        val hasDebtNotices = synchronized(NativeJsonStore) {
            val state = runCatching { ReminderNotifications.readState(context) }.getOrNull() ?: return
            val debts = ReminderNotifications.debts(state)
            ReminderNotifications.reconcile(context, debts, enabled)
            val recurring = RecurringReminder.fromState(state)
            ReminderNotifications.reconcileRecurring(context, recurring)
            if (BirthdayReminder.dueYear(state) == null) {
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager)?.cancel(BirthdayReminder.ID)
            }
            debts.isNotEmpty() || recurring.isNotEmpty() || BirthdayReminder.enabled(state) ||
                BankMaintenance.hasEnabled(NativeJsonStore.readState(context, setOf("accounts")))
        }
        if (!enabled && !hasDebtNotices) {
            existing?.let { alarm.cancel(it); it.cancel() }
            prefs.edit().remove(SCHEDULE_KEY).remove("daily_reminder_next_millis").apply()
            return
        }
        val exact = canScheduleExact(context)
        val scheduleKey = "${hour.coerceIn(0, 23)}:${minute.coerceIn(0, 59)}:${TimeZone.getDefault().id}:$exact"
        val now = System.currentTimeMillis()
        val previous = prefs.getLong("daily_reminder_next_millis", 0L)
        val sameSchedule = prefs.getString(SCHEDULE_KEY, "") == scheduleKey
        // Give a delayed alarm a short grace period, but repair a stale PendingIntent
        // after a missed delivery instead of leaving reminders disabled indefinitely.
        if (!force && existing != null && sameSchedule && previous > now - 15 * 60 * 1000L) return
        val pending = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarm.cancel(pending)
        val next = nextReminderTime(hour, minute, now)
        val today = Calendar.getInstance().apply { timeInMillis = now }
        val nextDay = Calendar.getInstance().apply { timeInMillis = next }
        val missedToday = !force && sameSchedule && previous in 1..now &&
            DebtReminder.dayNumber(nextDay) > DebtReminder.dayNumber(today)
        val trigger = if (missedToday) now + 1000L else next
        var scheduledExactly = exact
        try {
            if (exact) {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
            } else {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
            }
        } catch (_: SecurityException) {
            // Permission can be revoked between checking it and scheduling.
            scheduledExactly = false
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger, pending)
        }
        prefs.edit()
            .putString(SCHEDULE_KEY, if (scheduledExactly == exact) scheduleKey else "")
            .putLong("daily_reminder_next_millis", trigger)
            .apply()
    }

    fun canScheduleExact(context: Context): Boolean {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()
    }

    fun status(context: Context): Map<String, Any> {
        createChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelEnabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            manager.getNotificationChannel(CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE
        return mapOf(
            "exactAllowed" to canScheduleExact(context),
            "notificationsAllowed" to (manager.areNotificationsEnabled() && channelEnabled),
            "nextReminderMillis" to NativeJsonStore.prefs(context).getLong("daily_reminder_next_millis", 0L)
        )
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Recordatorios",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Movimientos, deudas y recurrentes pendientes"
        }
        manager.createNotificationChannel(channel)
    }

    internal fun nextReminderTime(
        hour: Int,
        minute: Int,
        now: Long = System.currentTimeMillis(),
        zone: TimeZone = TimeZone.getDefault()
    ): Long {
        val calendar = Calendar.getInstance(zone).apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
            set(Calendar.MINUTE, minute.coerceIn(0, 59))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (calendar.timeInMillis <= now) {
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        return calendar.timeInMillis
    }
}
