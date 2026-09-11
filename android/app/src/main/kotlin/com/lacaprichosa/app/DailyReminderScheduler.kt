package com.lacaprichosa.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object DailyReminderScheduler {
    const val CHANNEL_ID = "sin_rial_daily_movements"
    private const val REQUEST_CODE = 1900

    fun schedule(context: Context) {
        val state = NativeJsonStore.readState(context)
        val enabled = state.optBoolean("dailyMovementReminderEnabled", true)
        val hour = state.optInt("dailyReminderHour", 19).coerceIn(0, 23)
        val minute = state.optInt("dailyReminderMinute", 0).coerceIn(0, 59)
        schedule(context, enabled, hour, minute)
    }

    fun schedule(context: Context, enabled: Boolean, hour: Int, minute: Int) {
        createChannel(context)
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, DailyReminderReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarm.cancel(pending)
        alarm.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextReminderTime(hour.coerceIn(0, 23), minute.coerceIn(0, 59)),
            AlarmManager.INTERVAL_DAY,
            pending
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

    private fun nextReminderTime(hour: Int, minute: Int): Long {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (calendar.timeInMillis <= System.currentTimeMillis()) {
            calendar.add(Calendar.DAY_OF_YEAR, 1)
        }
        return calendar.timeInMillis
    }
}
