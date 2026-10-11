package site.bwdy.brewdiary

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Home-screen widgets: Flutter saves the cards / counts, then asks us to redraw.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brewdiary/widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    MosaicWidget.refreshAll(applicationContext)
                    result.success(null)
                }
                "quick" -> {
                    QuickLogWidget.setCounts(applicationContext, call.argument<Int>("water") ?: 0, call.argument<Int>("cigarettes") ?: 0)
                    result.success(null)
                }
                "split" -> {
                    SplitWidget.refreshAll(applicationContext)
                    result.success(null)
                }
                // "Add to home screen" from the app: Android shows its own confirm sheet
                // and places the widget. False when the launcher can't pin widgets.
                "pin" -> {
                    val cls = when (call.argument<String>("which")) {
                        "mosaic" -> MosaicWidget::class.java
                        "quick" -> QuickLogWidget::class.java
                        "split" -> SplitWidget::class.java
                        else -> null
                    }
                    val manager = AppWidgetManager.getInstance(applicationContext)
                    if (cls != null && manager.isRequestPinAppWidgetSupported) {
                        result.success(manager.requestPinAppWidget(ComponentName(applicationContext, cls), null, null))
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
