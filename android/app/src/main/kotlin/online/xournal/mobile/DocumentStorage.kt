package online.xournal.mobile

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/** Access documents chosen by the user through Android's document picker. */
object DocumentStorage {
    fun register(messenger: BinaryMessenger, resolver: ContentResolver) {
        MethodChannel(messenger, "online.xournal.mobile/documents",
            StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                try {
                    val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                    require(uri.scheme == "content") { "Expected a content URI" }
                    when (call.method) {
                        "read" -> {
                            val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
                                ?: throw IllegalStateException("Document is unavailable")
                            result.success(bytes)
                        }
                        "write" -> {
                            val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                            val stream = resolver.openOutputStream(uri, "wt")
                                ?: throw IllegalStateException("Document is not writable")
                            stream.use { it.write(bytes); it.flush() }
                            result.success(null)
                        }
                        "exists" -> {
                            val exists = try {
                                resolver.openFileDescriptor(uri, "r")?.use { true } ?: false
                            } catch (_: Exception) { false }
                            result.success(exists)
                        }
                        "retain" -> {
                            val retained = try {
                                resolver.takePersistableUriPermission(uri,
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                                true
                            } catch (_: SecurityException) { false }
                            result.success(retained)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("document_access", error.message, null)
                }
            }
    }
}
