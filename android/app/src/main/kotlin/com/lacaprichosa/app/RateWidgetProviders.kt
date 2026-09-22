package com.lacaprichosa.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Shader
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.floor

class UsdRateWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) = RateWidgetRenderer.updateAll(context, UsdRateWidgetProvider::class.java, "USD")
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        RateUpdateScheduler.refreshSoon(context)
        ids.forEach { manager.updateAppWidget(it, RateWidgetRenderer.buildViews(context, "USD", manager.getAppWidgetOptions(it))) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, RateWidgetRenderer.buildViews(context, "USD", options))
    }
}
class EurRateWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) = RateWidgetRenderer.updateAll(context, EurRateWidgetProvider::class.java, "EUR")
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        RateUpdateScheduler.refreshSoon(context)
        ids.forEach { manager.updateAppWidget(it, RateWidgetRenderer.buildViews(context, "EUR", manager.getAppWidgetOptions(it))) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, RateWidgetRenderer.buildViews(context, "EUR", options))
    }
}
object RateWidgetRenderer {
    fun updateAll(context: Context, provider: Class<*>, currency: String) {
        val manager = AppWidgetManager.getInstance(context)
        manager.getAppWidgetIds(ComponentName(context, provider)).forEach {
            manager.updateAppWidget(it, buildViews(context, currency, manager.getAppWidgetOptions(it)))
        }
    }

    fun history(state: JSONObject, currency: String): List<Double> {
        val effective = state.optString(if (currency == "EUR") "eurRateEffectiveDate" else "rateEffectiveDate")
        if (effective.isBlank()) return emptyList()
        val quotes = BcvRatePolicy.saved(state)
        return (0 until quotes.length()).map { quotes.getJSONObject(it) }
            .filter { it.getString("effective_date") <= effective }
            .takeLast(14).map { it.getDouble(currency) }
    }

    fun buildViews(context: Context, currency: String, options: Bundle = Bundle()): RemoteViews {
        val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 56)
        val views = RemoteViews(context.packageName, if (height < 70) R.layout.rate_widget_compact else R.layout.rate_widget)
        val state = runCatching { NativeJsonStore.readMain(context) }.getOrElse { JSONObject() }
        val theme = WidgetAppearance(state)
        val compact = height < 100
        val tiny = height < 70
        val pad = ((if (tiny) 4 else if (compact) 8 else 12) * context.resources.displayMetrics.density).toInt()
        val side = (12 * context.resources.displayMetrics.density).toInt()
        views.setViewPadding(R.id.rate_root, side, pad, side, pad)
        views.setViewVisibility(R.id.rate_updated, if (tiny) View.GONE else View.VISIBLE)
        views.setInt(R.id.rate_root, "setBackgroundResource", theme.background)
        views.setViewVisibility(R.id.rate_icon, if (compact) View.GONE else View.VISIBLE)
        views.setImageViewResource(R.id.rate_icon, if (currency == "EUR") R.drawable.widget_eu else R.drawable.widget_us)
        views.setTextColor(R.id.rate_value, theme.ink)
        views.setTextColor(R.id.rate_pair, theme.accent)
        views.setTextColor(R.id.rate_updated, theme.muted)
        if (tiny) {
            views.setTextViewTextSize(R.id.rate_value, TypedValue.COMPLEX_UNIT_SP, 20f)
            views.setTextViewTextSize(R.id.rate_updated, TypedValue.COMPLEX_UNIT_SP, 9f)
            views.setTextViewTextSize(R.id.rate_pair, TypedValue.COMPLEX_UNIT_SP, 10f)
        }
        views.setInt(R.id.rate_updated, "setMaxLines", if (compact) 1 else 2)
        val current = state.optDouble(if (currency == "EUR") "eurRate" else "rate", 0.0)
        val previous = state.optDouble(if (currency == "EUR") "previousEurRate" else "previousRate", 0.0)
        val valid = current.isFinite() && current > 0
        val change = if (valid && previous.isFinite() && previous > 0) (current / previous - 1) * 100 else null
        views.setTextViewText(R.id.rate_pair, "$currency / BCV")
        val rateLabel = if (valid) "Bs " + WidgetAppearance.amount(floor(current * 100) / 100) else "Sin tasa"
        views.setTextViewText(R.id.rate_value, rateLabel)
        views.setViewVisibility(R.id.rate_change, if (change == null) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.rate_change, change?.let {
            (if (it >= 0) "+" else "") + WidgetAppearance.amount(it) + "%"
        } ?: "")
        views.setTextColor(R.id.rate_change, if ((change ?: 0.0) >= 0) theme.green else theme.red)

        val effective = state.optString(if (currency == "EUR") "eurRateEffectiveDate" else "rateEffectiveDate")
        val status = state.optString(if (currency == "EUR") "eurRateFetchStatus" else "rateFetchStatus")
        val millis = state.optLong(if (currency == "EUR") "eurLastRateMillis" else "lastRateMillis", 0L)
        val today = BcvRatePolicy.dateKey(System.currentTimeMillis())
        val stamp = if (millis > 0) SimpleDateFormat("dd/MM HH:mm", Locale.forLanguageTag("es-VE"))
            .apply { timeZone = BcvRatePolicy.zone }.format(Date(millis)) else ""
        val label = when {
            !valid -> "Sin tasa guardada"
            status == "offline" -> "Sin conexi\u00f3n"
            status == "error" -> "No se pudo actualizar"
            effective > today -> "Adelantada: $effective"
            effective.isNotBlank() && effective < today -> "\u00daltima publicada: $effective"
            effective.isNotBlank() -> "BCV $effective"
            else -> "Tasa guardada"
        }
        views.setTextViewText(R.id.rate_updated, label + if (!compact && stamp.isNotBlank()) "\nConsulta $stamp" else "")
        views.setContentDescription(R.id.rate_root, "$currency BCV. $rateLabel. $label")
        val points = history(state, currency)
        val graph = valid && height >= 160 && points.size >= 2
        views.setViewVisibility(R.id.rate_chart, if (graph) View.VISIBLE else View.GONE)
        if (graph) views.setImageViewBitmap(R.id.rate_chart, chart(points, theme.accent))
        views.setOnClickPendingIntent(R.id.rate_root, QuickAccessActivity.pendingIntent(context, "calculator"))
        return views
    }

    private fun chart(points: List<Double>, color: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(600, 100, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val low = points.min()
        val high = points.max()
        val path = Path()
        points.forEachIndexed { i, value ->
            val x = 4f + 592f * i / (points.size - 1)
            val y = if (high == low) 50f else 90f - (80 * (value - low) / (high - low)).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        val fill = Path(path).apply { lineTo(596f, 100f); lineTo(4f, 100f); close() }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, 100f,
            (color and 0x00ffffff) or 0x44000000, color and 0x00ffffff, Shader.TileMode.CLAMP)
        canvas.drawPath(fill, paint)
        paint.shader = null
        paint.color = color
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 4f
        paint.strokeJoin = Paint.Join.ROUND
        canvas.drawPath(path, paint)
        return bitmap
    }
}
