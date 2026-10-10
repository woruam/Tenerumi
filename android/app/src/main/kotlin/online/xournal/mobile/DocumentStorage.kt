package online.xournal.mobile

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.io.File
import android.content.Context
import java.security.MessageDigest

/** Access documents chosen by the user through Android's document picker. */
object DocumentStorage {
    fun register(messenger: BinaryMessenger, resolver: ContentResolver, context: Context) {
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
                            val limit = call.argument<Int>("maxBytes") ?: (128 * 1024 * 1024)
                            require(limit in 1..(513 * 1024 * 1024)) { "Invalid read limit" }
                            val bytes = resolver.openInputStream(uri)?.use { input ->
                                val output = ByteArrayOutputStream()
                                val buffer = ByteArray(65536)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    require(output.size().toLong() + count <= limit) { "Document exceeds read limit" }
                                    output.write(buffer, 0, count)
                                }
                                output.toByteArray()
                            }
                                ?: throw IllegalStateException("Document is unavailable")
                            result.success(bytes)
                        }
                        "hash" -> {
                            val limit = call.argument<Int>("maxBytes") ?: (128 * 1024 * 1024)
                            require(limit in 1..(513 * 1024 * 1024))
                            val digest = MessageDigest.getInstance("SHA-256")
                            resolver.openInputStream(uri)?.use { input ->
                                val buffer = ByteArray(65536)
                                var total = 0L
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    require(total <= limit)
                                    digest.update(buffer, 0, count)
                                }
                            } ?: throw IllegalStateException("Document unavailable")
                            result.success(digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) })
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
                        "writeFromFile" -> {
                            val source = File(requireNotNull(call.argument<String>("source"))).canonicalFile
                            val root = File(context.applicationInfo.dataDir).canonicalFile
                            require(source.path.startsWith(root.path + File.separator) && source.name in listOf("backup.zip", "export.pdf") && source.parentFile?.parentFile?.name == "backup-staging") { "Expected private export staging" }
                            require(source.length() in 1..(513 * 1024 * 1024L)) { "Backup too large" }
                            resolver.openOutputStream(uri, "wt")?.use { output ->
                                source.inputStream().use { input ->
                                    val buffer = ByteArray(65536)
                                    var total = 0L
                                    while (true) {
                                        val count = input.read(buffer)
                                        if (count < 0) break
                                        total += count
                                        require(total <= 513 * 1024 * 1024L)
                                        output.write(buffer, 0, count)
                                    }
                                    output.flush()
                                }
                            } ?: throw IllegalStateException("Backup destination unavailable")
                            val expected = source.inputStream().use { input ->
                                val digest = java.security.MessageDigest.getInstance("SHA-256")
                                val buffer = ByteArray(65536)
                                while (true) { val n=input.read(buffer); if(n<0) break; digest.update(buffer,0,n) }
                                digest.digest()
                            }
                            val actual = resolver.openInputStream(uri)?.use { input ->
                                val digest=java.security.MessageDigest.getInstance("SHA-256")
                                val buffer=ByteArray(65536); var size=0L
                                while(true) { val n=input.read(buffer); if(n<0)break;size+=n;require(size<=513*1024*1024L);digest.update(buffer,0,n) }
                                digest.digest()
                            } ?: throw IllegalStateException("Cannot verify exported backup")
                            require(expected.contentEquals(actual)) { "Export verification failed; private candidate retained" }
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
