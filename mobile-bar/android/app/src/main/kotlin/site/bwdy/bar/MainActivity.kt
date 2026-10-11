package site.bwdy.bar

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The bar's and kitchen's tablets and the ready board keep the screen on while they're
    // open (brewdiary/awake); everywhere else the phone sleeps as usual.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brewdiary/awake").setMethodCallHandler { call, result ->
            if (call.method == "set") {
                if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
