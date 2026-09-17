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
        val state = NativeJsonStore.readState(context)
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
        val debts = NativeJsonStore.readState(context).optJSONArray("debts")
        val hasDebtNotices = (0 until (debts?.length() ?: 0)).any { index ->
            val debt = debts?.optJSONObject(index)
            debt != null && debt.optBoolean("hasDueDate", true) &&
                debt.optBoolean("notifyDueDate", true) &&
                debt.optString("dueDate").isNotBlank() &&
                debt.optDouble("amount", 0.0) > debt.optDouble("paidAmount", 0.0)
        }
        if (!enabled && !hasDebtNotices) {
            existing?.let { alarm.cancel(it); it.cancel() }
            prefs.edit().remove(SCHEDULE_KEY).remove("daily_reminder_next_millis").apply()
            return
        }
        val exact = canScheduleExact(context)
        val scheduleKey = "${hour.coerceIn(0, 23)}:${minute.coerceIn(0, 59)}:${TimeZone.getDefault().id}:$exact"
        // Unrelated saves must not postpone an alarm already waiting to be delivered.
        if (!force && existing != null && prefs.getString(SCHEDULE_KEY, "") == scheduleKey) return
        val pending = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarm.cancel(pending)
        val trigger = nextReminderTime(hour, minute)
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
            "Recordatorio diario",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Recordatorio para registrar movimientos"
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
