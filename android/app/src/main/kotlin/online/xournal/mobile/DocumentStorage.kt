package online.xournal.mobile

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
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
                        "lastModified" -> {
                            val modified = try {
                                resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
                                    null, null, null)?.use { cursor ->
                                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
                                }
                            } catch (_: Exception) { null }
                            result.success(modified)
                        }
                        "read" -> {
                            val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
                                ?: throw IllegalStateException("Document is unavailable")
                            result.success(bytes)
                        }
                        "delete" -> {
                            if (!DocumentsContract.deleteDocument(resolver, uri)) {
                                throw IllegalStateException("Impossibile eliminare il documento")
                            }
                            result.success(null)
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
