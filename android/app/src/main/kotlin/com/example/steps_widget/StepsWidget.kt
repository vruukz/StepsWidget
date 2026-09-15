package com.example.steps_widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.os.Build
import android.widget.RemoteViews

class StepsWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val DEFAULT_ACCENT = 0xFF4ADE80.toInt()

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs: SharedPreferences = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )

            val steps = prefs.getLong("flutter.steps", 0L).toInt()
            val goal = prefs.getLong("flutter.goal", 10000L).toInt()
            val label = prefs.getString("flutter.label", "$steps / $goal") ?: "$steps / $goal"
            val accent = prefs.getLong("flutter.accent_color", DEFAULT_ACCENT.toLong()).toInt()

            val views = RemoteViews(context.packageName, R.layout.steps_widget)
            views.setTextViewText(R.id.widget_steps, steps.toString())
            views.setTextViewText(R.id.widget_label, label)
            views.setTextColor(R.id.widget_steps, accent)

            val progressPercent = ((steps.toFloat() / goal.toFloat()) * 100).toInt().coerceIn(0, 100)
            views.setProgressBar(R.id.widget_progress, 100, progressPercent, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setColorStateList(
                    R.id.widget_progress, "setProgressTintList", ColorStateList.valueOf(accent)
                )
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}