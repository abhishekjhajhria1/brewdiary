package site.bwdy.brewdiary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The home-screen widget: Flutter saves the month card, then asks us to redraw.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brewdiary/widget").setMethodCallHandler { call, result ->
            if (call.method == "refresh") {
                MosaicWidget.refreshAll(applicationContext)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
