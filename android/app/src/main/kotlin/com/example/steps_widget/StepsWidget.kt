package com.example.steps_widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import java.util.Calendar

class StepsWidget : AppWidgetProvider() {

    // Fallback path: the periodic call the system makes to onUpdate()
    // regardless of whether the app or StepsForegroundService is running.
    // The service (started on launch/boot) is what keeps the widget live
    // while walking; this just re-syncs it every updatePeriodMillis tick.
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val pendingResult = goAsync()
        refreshStepsFromSensor(context) {
            for (appWidgetId in appWidgetIds) {
                updateWidget(context, appWidgetManager, appWidgetId)
            }
            pendingResult.finish()
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val DEFAULT_ACCENT = 0xFF4ADE80.toInt()
        private const val SENSOR_TIMEOUT_MS = 4000L

        // Reads a fresh cumulative step-counter value from the sensor and
        // updates flutter.steps/label/step_date/step_baseline the same way
        // the Dart side does, so both stay consistent whichever one runs
        // first on a given day. Always calls [onDone] exactly once, even if
        // the sensor is unavailable or never reports in time.
        fun refreshStepsFromSensor(context: Context, onDone: () -> Unit) {
            val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
            val sensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
            if (sensorManager == null || sensor == null) {
                onDone()
                return
            }

            val handler = Handler(Looper.getMainLooper())
            var finished = false
            lateinit var listener: SensorEventListener

            fun finish() {
                if (finished) return
                finished = true
                sensorManager.unregisterListener(listener)
                handler.removeCallbacksAndMessages(null)
                onDone()
            }

            listener = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    applySensorValue(context, event.values[0].toLong())
                    finish()
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }

            sensorManager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
            handler.postDelayed({ finish() }, SENSOR_TIMEOUT_MS)
        }

        // Used by StepsForegroundService, which keeps its own persistent
        // sensor listener and already has a fresh reading on every call —
        // no need to register/wait for one here.
        fun applySensorValueAndUpdateWidgets(context: Context, sensorSteps: Long) {
            applySensorValue(context, sensorSteps)
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, StepsWidget::class.java))
            for (id in ids) {
                updateWidget(context, manager, id)
            }
        }

        private fun applySensorValue(context: Context, sensorSteps: Long) {
            val prefs: SharedPreferences = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )

            val calendar = Calendar.getInstance()
            // Matches the Dart side's `'${now.year}-${now.month}-${now.day}'`
            // (1-based month, no zero-padding) so a baseline reset triggered
            // by whichever side runs first is seen consistently by the other.
            val today = "${calendar.get(Calendar.YEAR)}-" +
                "${calendar.get(Calendar.MONTH) + 1}-" +
                "${calendar.get(Calendar.DAY_OF_MONTH)}"
            val savedDate = prefs.getString("flutter.step_date", "") ?: ""

            var baseline = prefs.getLong("flutter.step_baseline", -1L)
            if (savedDate != today) {
                baseline = -1L
            }
            if (baseline == -1L) {
                baseline = sensorSteps
            }

            val goal = prefs.getLong("flutter.goal", 10000L)
            val todaySteps = (sensorSteps - baseline).coerceIn(0L, 999999L)
            val label = if (todaySteps >= goal) "GOAL REACHED ✓" else "$todaySteps / $goal"

            prefs.edit()
                .putString("flutter.step_date", today)
                .putLong("flutter.step_baseline", baseline)
                .putLong("flutter.steps", todaySteps)
                .putString("flutter.label", label)
                .apply()
        }

        // "10000" -> "10k", "7500" -> "7.5k", "500" -> "500"
        fun formatGoalSuffix(goal: Long): String {
            if (goal < 1000) return "/$goal"
            val thousands = goal / 1000.0
            val text = if (thousands == thousands.toLong().toDouble()) {
                "${thousands.toLong()}k"
            } else {
                "${"%.1f".format(thousands)}k"
            }
            return "/$text"
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs: SharedPreferences = context.getSharedPreferences(
                PREFS_NAME, Context.MODE_PRIVATE
            )

            val steps = prefs.getLong("flutter.steps", 0L)
            val goal = prefs.getLong("flutter.goal", 10000L)
            val accent = prefs.getLong("flutter.accent_color", DEFAULT_ACCENT.toLong()).toInt()

            val views = RemoteViews(context.packageName, R.layout.steps_widget)
            views.setTextViewText(R.id.widget_steps, steps.toString())
            views.setTextViewText(R.id.widget_goal_suffix, formatGoalSuffix(goal))
            views.setTextColor(R.id.widget_steps, accent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
