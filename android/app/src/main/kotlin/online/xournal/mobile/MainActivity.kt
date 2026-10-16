package online.xournal.mobile

import android.hardware.display.DisplayManager
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "online.xournal.mobile/pen"
    private var methodChannel: MethodChannel? = null
    private var noteAudio: NoteAudio? = null
    private var externalDocuments: ExternalDocuments? = null
    private val displayManager by lazy { getSystemService(DisplayManager::class.java) }
    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = requestHighRefreshRate()
        override fun onDisplayRemoved(displayId: Int) = requestHighRefreshRate()
        override fun onDisplayChanged(displayId: Int) {
            if (window.decorView.display?.displayId == displayId) requestHighRefreshRate()
        }
    }

    override fun onResume() {
        super.onResume()
        noteAudio?.resume()
        displayManager.registerDisplayListener(displayListener, Handler(Looper.getMainLooper()))
        window.decorView.post { requestHighRefreshRate() }
    }

    override fun onPause() {
        noteAudio?.interrupt(leaving = true)
        displayManager.unregisterDisplayListener(displayListener)
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) requestHighRefreshRate()
    }

    private fun requestHighRefreshRate() {
        val display = window.decorView.display ?: return
        val current = display.mode
        val preferred = DisplayModePolicy.select(
            current.physicalWidth, current.physicalHeight,
            display.supportedModes.map {
                RefreshMode(it.modeId, it.physicalWidth, it.physicalHeight, it.refreshRate)
            }
        ) ?: return
        val attributes = window.attributes
        // Updating only on a change prevents a display-listener feedback loop.
        if (attributes.preferredDisplayModeId != preferred.id) {
            attributes.preferredDisplayModeId = preferred.id
            window.attributes = attributes
        }
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN ||
            event.actionMasked == MotionEvent.ACTION_POINTER_DOWN) {
            val tool = event.getToolType(event.actionIndex)
            if (tool == MotionEvent.TOOL_TYPE_STYLUS || tool == MotionEvent.TOOL_TYPE_ERASER) {
                // Request on the actual Flutter input target, before it receives DOWN.
                // Keep Flutter's normal pointer path: no duplicate/custom event stream.
                findFlutterView(window.decorView)?.requestUnbufferedDispatch(event)
            }
        }
        return super.dispatchTouchEvent(event)
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutterView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        noteAudio = NoteAudio(this, flutterEngine.dartExecutor.binaryMessenger)
        DocumentStorage.register(flutterEngine.dartExecutor.binaryMessenger, contentResolver, this)
        OptionalFeatures.register(flutterEngine.dartExecutor.binaryMessenger)
        externalDocuments = ExternalDocuments(flutterEngine.dartExecutor.binaryMessenger, contentResolver)
        externalDocuments?.accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        externalDocuments?.accept(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (noteAudio?.permissionResult(requestCode, grantResults) != true) super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        noteAudio?.close(); noteAudio = null
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // repeatCount == 0: reagiamo solo alla PRIMA pressione, NON alle ripetizioni
        // automatiche del tasto tenuto premuto (che causavano toggle multipli ed erratici).
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
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
