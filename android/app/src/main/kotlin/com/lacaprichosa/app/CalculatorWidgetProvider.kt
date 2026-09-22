package com.lacaprichosa.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject

class CalculatorWidgetProvider : AppWidgetProvider() {
    companion object {
        fun buildViews(context: Context): RemoteViews {
            val theme = WidgetAppearance(runCatching { NativeJsonStore.readMain(context) }.getOrElse { JSONObject() })
            return RemoteViews(context.packageName, R.layout.calculator_widget).apply {
                setInt(R.id.calculator_root, "setBackgroundResource", theme.background)
                setTextColor(R.id.calculator_title, theme.ink)
                setInt(R.id.calculator_icon, "setColorFilter", theme.accent)
                setOnClickPendingIntent(R.id.calculator_root, QuickAccessActivity.pendingIntent(context, "calculator"))
            }
        }
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, CalculatorWidgetProvider::class.java))
                .forEach { manager.updateAppWidget(it, buildViews(context)) }
        }
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, buildViews(context)) }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, buildViews(context))
    }
}
