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
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.TimeUnit

class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            DailyReminderScheduler.schedule(context)
            return
        }

        DailyReminderScheduler.createChannel(context)
        val launchIntent = (context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            1901,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (dailyMovementReminderEnabled(context)) {
            manager.notify(
                1901,
                notification(
                    context,
                    "Sin Rial",
                    "Registra tus movimientos de hoy.",
                    contentIntent
                )
            )
        }
        notifyDebtDueDates(context, manager, contentIntent)
        DailyReminderScheduler.schedule(context)
    }

    private fun notification(
        context: Context,
        title: String,
        text: String,
        contentIntent: PendingIntent
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, DailyReminderScheduler.CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()
    }

    private fun notifyDebtDueDates(
        context: Context,
        manager: NotificationManager,
        contentIntent: PendingIntent
    ) {
        val state = NativeJsonStore.readState(context)
        val debts = state.optJSONArray("debts") ?: return
        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.time
        val exactReminderDays = setOf(7L, 5L, 3L, 1L, 0L)

        for (index in 0 until debts.length()) {
            val debt = debts.optJSONObject(index) ?: continue
            if (debt.optBoolean("hasDueDate", true).not()) continue
            if (debt.optBoolean("notifyDueDate", true).not()) continue
            val dueDateText = debt.optString("dueDate", "").trim()
            if (dueDateText.isEmpty()) continue
            val amount = debt.optDouble("amount", 0.0)
            val paid = debt.optDouble("paidAmount", 0.0)
            if (amount > 0.0 && paid >= amount) continue
            val dueDate = parseDueDate(dueDateText) ?: continue
            val daysLeft = TimeUnit.MILLISECONDS.toDays(dueDate.time - today.time)
            if (daysLeft !in exactReminderDays && daysLeft >= 0) continue

            val kind = if (debt.optString("kind") == "receivable") "cobro" else "pago"
            val title = debt.optString("title", "").ifBlank {
                if (kind == "cobro") "Por cobrar" else "Por pagar"
            }
            val timeText = when {
                daysLeft > 1 -> "vence en $daysLeft días"
                daysLeft == 1L -> "vence mañana"
                daysLeft == 0L -> "vence hoy"
                else -> "está atrasado ${-daysLeft} día(s)"
            }
            manager.notify(
                2200 + index,
                notification(
                    context,
                    "Sin Rial: $kind pendiente",
                    "$title $timeText.",
                    contentIntent
                )
            )
        }
    }

    private fun dailyMovementReminderEnabled(context: Context): Boolean {
        val state = NativeJsonStore.readState(context)
        return state.optBoolean("dailyMovementReminderEnabled", true)
    }

    private fun parseDueDate(value: String) =
        listOf("dd/MM/yyyy", "yyyy-MM-dd").firstNotNullOfOrNull { pattern ->
            runCatching {
                SimpleDateFormat(pattern, Locale.US).apply {
                    isLenient = false
                }.parse(value)
            }.getOrNull()
        }
}
