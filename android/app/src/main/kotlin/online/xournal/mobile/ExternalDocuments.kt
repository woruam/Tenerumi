package online.xournal.mobile

import android.content.ContentResolver
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Keep URI grants on the activity intent, and read via DocumentStorage. */
class ExternalDocuments(messenger: BinaryMessenger, private val resolver: ContentResolver) {
    private val pending = mutableListOf<Map<String, String>>()
    private var listening = false
    private val channel = MethodChannel(messenger, "online.xournal.mobile/external_documents")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialDocuments", "listen" -> {
                    if (call.method == "listen") listening = true
                    val documents = pending.toList()
                    pending.clear()
                    result.success(documents)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun accept(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "content" && uri.scheme != "file") return
        val type = intent.type ?: try { resolver.getType(uri) } catch (_: Exception) { null }
        var name = uri.lastPathSegment ?: "Documento.pdf"
        if (uri.scheme == "content") {
            try {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
                }
            } catch (_: Exception) { /* URI content remains readable without a display name. */ }
        }
        if (type != "application/pdf" && !name.endsWith(".pdf", ignoreCase = true)) return
        val document = mapOf("uri" to uri.toString(), "name" to name)
        if (listening) channel.invokeMethod("openPdf", document) else pending.add(document)
    }
}
