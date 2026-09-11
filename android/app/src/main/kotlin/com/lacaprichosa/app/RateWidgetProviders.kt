package com.lacaprichosa.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Locale
import kotlin.math.abs

class UsdRateWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            RateWidgetRenderer.updateAll(context, UsdRateWidgetProvider::class.java, "USD")
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, RateWidgetRenderer.buildViews(context, "USD")) }
    }
}

class EurRateWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            RateWidgetRenderer.updateAll(context, EurRateWidgetProvider::class.java, "EUR")
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, RateWidgetRenderer.buildViews(context, "EUR")) }
    }
}

object RateWidgetRenderer {
    fun updateAll(context: Context, provider: Class<*>, currency: String) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        ids.forEach { manager.updateAppWidget(it, buildViews(context, currency)) }
    }

    fun buildViews(context: Context, currency: String): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.rate_widget)
        val state = readState(context)
        val current = if (currency == "EUR") state.optDouble("eurRate", 0.0) else state.optDouble("rate", 0.0)
        val previous = if (currency == "EUR") {
            state.optDouble("previousEurRate", 0.0)
        } else {
            state.optDouble("previousRate", 0.0)
        }
        val updated = if (currency == "EUR") {
            state.optString("eurRateEffectiveDate", state.optString("rateEffectiveDate", ""))
        } else {
            state.optString("rateEffectiveDate", state.optString("lastRateDate", ""))
        }
        val percent = if (current > 0.0 && previous > 0.0) ((current - previous) / previous) * 100.0 else 0.0
        val accent = themeAccent(state.optString("themeColor", "emerald"))
        views.setTextViewText(R.id.rate_pair, "$currency/VES")
        views.setTextViewText(R.id.rate_value, if (current > 0.0) "Bs ${formatRate(current)}" else "Sin tasa")
        views.setTextViewText(R.id.rate_change, formatPercent(percent))
        views.setTextViewText(R.id.rate_updated, if (updated.isNotBlank()) "Actualizado $updated" else "Abre Sin Rial para actualizar")
        views.setTextColor(R.id.rate_change, if (percent >= 0.0) Color.rgb(88, 190, 134) else Color.rgb(196, 30, 30))
        views.setTextColor(R.id.rate_pair, Color.WHITE)
        views.setOnClickPendingIntent(R.id.rate_root, openAppIntent(context, currency))
        return views
    }

    private fun readState(context: Context): JSONObject {
        return NativeJsonStore.readState(context)
    }

    private fun openAppIntent(context: Context, currency: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "com.lacaprichosa.app.RATE_WIDGET_$currency"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(context, currency.hashCode(), intent, flags)
    }

    private fun themeAccent(key: String): Int {
        return when (key) {
            "wine" -> Color.rgb(196, 30, 30)
            "amber" -> Color.rgb(185, 133, 24)
            "cyan" -> Color.rgb(35, 124, 154)
            "teal" -> Color.rgb(36, 123, 123)
            "violet" -> Color.rgb(120, 87, 166)
            "rose" -> Color.rgb(184, 78, 104)
            "lime" -> Color.rgb(112, 141, 43)
            "navy" -> Color.rgb(48, 80, 124)
            "sky" -> Color.rgb(47, 128, 201)
            "mint" -> Color.rgb(43, 138, 110)
            "orange" -> Color.rgb(198, 106, 36)
            "magenta" -> Color.rgb(166, 61, 128)
            "graphite" -> Color.rgb(77, 86, 99)
            else -> Color.rgb(3, 103, 74)
        }
    }

    private fun formatRate(value: Double): String {
        return String.format(Locale.US, "%.2f", value).replace(".", ",")
    }

    private fun formatPercent(value: Double): String {
        if (abs(value) < 0.0001) return "+0,00%"
        val sign = if (value >= 0.0) "+" else ""
        return sign + String.format(Locale.US, "%.2f", value).replace(".", ",") + "%"
    }
}
