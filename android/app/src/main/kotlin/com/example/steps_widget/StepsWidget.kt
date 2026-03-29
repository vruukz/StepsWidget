package com.example.steps_widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
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

            val views = RemoteViews(context.packageName, R.layout.steps_widget)
            views.setTextViewText(R.id.widget_steps, steps.toString())
            views.setTextViewText(R.id.widget_label, label)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}