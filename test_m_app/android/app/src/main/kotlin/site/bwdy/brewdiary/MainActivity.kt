package site.bwdy.brewdiary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                else -> result.notImplemented()
            }
        }
    }
}
