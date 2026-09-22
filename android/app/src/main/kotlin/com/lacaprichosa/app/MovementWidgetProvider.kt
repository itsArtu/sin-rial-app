package com.lacaprichosa.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews

class MovementWidgetProvider : AppWidgetProvider() {
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, MovementWidgetProvider::class.java))
            ids.forEach { manager.updateAppWidget(it, buildViews(context, manager.getAppWidgetOptions(it))) }
        }

        fun buildViews(context: Context, options: Bundle = Bundle()): RemoteViews {
            val expanded = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 56) >= 110
            val views = RemoteViews(context.packageName, if (expanded) R.layout.movement_widget_expanded else R.layout.movement_widget)
            val theme = WidgetAppearance(runCatching { NativeJsonStore.readMain(context) }.getOrElse { org.json.JSONObject() })
            views.setInt(R.id.widget_surface, "setBackgroundResource", theme.background)
            views.setTextColor(R.id.widget_title, theme.ink)
            for (id in intArrayOf(R.id.widget_income, R.id.widget_expense)) {
                views.setInt(id, "setBackgroundResource", theme.button)
            }
            views.setTextColor(R.id.widget_income, theme.green)
            views.setTextColor(R.id.widget_expense, theme.red)
            if (expanded) {
                views.setTextColor(R.id.widget_caption, theme.muted)
                views.setInt(R.id.widget_transfer, "setBackgroundResource", theme.button)
                views.setTextColor(R.id.widget_transfer, theme.accent)
                views.setOnClickPendingIntent(R.id.widget_transfer, movementIntent(context, "transfer", 2103))
            }
            views.setOnClickPendingIntent(
                R.id.widget_income,
                movementIntent(context, "income", 2101)
            )
            views.setOnClickPendingIntent(
                R.id.widget_expense,
                movementIntent(context, "expense", 2102)
            )
            return views
        }

        private fun movementIntent(context: Context, type: String, requestCode: Int): PendingIntent {
            if (type == "income" || type == "expense") return QuickAccessActivity.pendingIntent(context, type)
            val intent = Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_WIDGET_MOVEMENT
                putExtra(MainActivity.EXTRA_WIDGET_MOVEMENT_TYPE, type)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            return PendingIntent.getActivity(context, requestCode, intent, flags)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetManager.getAppWidgetOptions(appWidgetId)))
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, buildViews(context, options))
    }
}
