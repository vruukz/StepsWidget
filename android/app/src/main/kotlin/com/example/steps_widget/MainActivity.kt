package com.example.steps_widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.steps_widget/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "updateWidget") {
                    val manager = AppWidgetManager.getInstance(this)
                    val ids = manager.getAppWidgetIds(
                        ComponentName(this, StepsWidget::class.java)
                    )
                    for (id in ids) {
                        StepsWidget.updateWidget(this, manager, id)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}