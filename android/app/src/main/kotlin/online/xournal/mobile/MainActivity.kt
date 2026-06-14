package online.xournal.mobile

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "online.xournal.mobile/pen"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            // Tasto 1: Page Down (di solito quello vicino alla punta)
            if (event.keyCode == KeyEvent.KEYCODE_PAGE_DOWN) {
                methodChannel?.invokeMethod("redmiPenPageDown", null)
                return true
            } 
            // Tasto 2: Page Up (di solito quello superiore)
            else if (event.keyCode == KeyEvent.KEYCODE_PAGE_UP) {
                methodChannel?.invokeMethod("redmiPenPageUp", null)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }
}