package com.lacaprichosa.app

import android.content.BroadcastReceiver
import android.util.Log
import java.util.concurrent.Executors

internal object ReminderWork {
    val executor = Executors.newSingleThreadExecutor()

    fun run(pending: BroadcastReceiver.PendingResult?, action: () -> Unit) {
        executor.execute {
            try {
                action()
            } catch (error: Exception) {
                Log.w("SinRialReminders", "No se pudo procesar el recordatorio", error)
            } finally {
                pending?.finish()
            }
        }
    }
}
