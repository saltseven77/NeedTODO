package com.needtodo.needtodo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.needtodo/platform")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "widgetUpdate" -> {
                    val json = call.arguments as? String ?: "{}"
                    getSharedPreferences("needtodo_widget", MODE_PRIVATE).edit().putString("snapshot", json).apply()
                    CalendarWidget.updateAll(this)
                    result.success(null)
                }
                "widgetPin" -> {
                    val manager = AppWidgetManager.getInstance(this)
                    if (Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported) {
                        result.success(manager.requestPinAppWidget(ComponentName(this, CalendarWidget::class.java), null, null))
                    } else result.success(false)
                }
                "widgetLaunch" -> { result.success(intent?.getStringExtra("date")); intent?.removeExtra("date") }
                else -> result.notImplemented()
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra("date")?.let { channel?.invokeMethod("openDate", it) }
    }
}
