package com.lacaprichosa.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Build

object WidgetPinning {
    fun request(context: Context, type: String?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val provider = when (type) {
            "movement" -> MovementWidgetProvider::class.java
            "USD" -> UsdRateWidgetProvider::class.java
            "EUR" -> EurRateWidgetProvider::class.java
            "calculator" -> CalculatorWidgetProvider::class.java
            else -> return false
        }
        return runCatching {
            val manager = AppWidgetManager.getInstance(context)
            manager.isRequestPinAppWidgetSupported &&
                manager.requestPinAppWidget(ComponentName(context, provider), null, null)
        }.getOrDefault(false)
    }
}
