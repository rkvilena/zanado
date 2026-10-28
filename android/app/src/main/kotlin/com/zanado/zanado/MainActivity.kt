package com.zanado.zanado

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * Zanado storage channel (user-visible storage).
 *
 * Saves files into the PUBLIC Downloads directory under `Download/zanado/`
 * using MediaStore, so they are visible to the system file manager and other
 * apps (SHAREit-like behavior). No storage permissions are needed on API 29+:
 * MediaStore contributions made by this app can be read/deleted by this app.
 *
 * The `IS_PENDING` flag plays the same role as the Dart-side `.part` file:
 * an entry is inserted as pending, fully written + size-verified, and only
 * then published (IS_PENDING=0). A failed write leaves no completed file.
 *
 * Requires API 29+ (MediaStore.Downloads). For older devices this channel
 * returns an error; the app targets modern Android devices.
 */
class MainActivity : FlutterActivity() {
    private val tag = "zanado.storage"
    private val channelName = "zanado/storage"
    private val relativePath = "Download/zanado/"

    // MediaStore publication copies the whole file (multi-GB) synchronously;
    // on the main thread this blocked the UI long enough for Android to raise
    // an ANR ("MainThread worked timeout" after a 3.56 GB receive).
    // All publish work therefore runs on a dedicated background executor.
    private val publishExecutor = Executors.newSingleThreadExecutor()
    // MethodChannel results must be delivered on the main thread.
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        // In-flight publishes finish but their results are discarded after
        // detach (deliverResult guards against replying to a dead engine).
        publishExecutor.shutdown()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "directoryPath" -> result.success(storageDirPath())
                        "list" -> result.success(listEntries())
                        "saveFromFile" -> {
                            val displayName = call.argument<String>("displayName")!!
                            val sourcePath = call.argument<String>("sourcePath")!!
                            // Caller-owned source: publish a copy, never delete it.
                            runPublishInBackground(result) {
                                publishFile(displayName, File(sourcePath), deleteSource = false)
                            }
                        }
                        "commitFromPath" -> {
                            val displayName = call.argument<String>("displayName")!!
                            val partPath = call.argument<String>("partPath")!!
                            // Platform channel encodes Dart ints as Integer when
                            // they fit; requiring Long here crashes on any
                            // file under ~2 GB. Accept both Number widths.
                            val expectedSize = call.argument<Number>("expectedSize")?.toLong()
                            runPublishInBackground(result) {
                                publishFile(displayName, File(partPath), expectedSize, deleteSource = true)
                            }
                        }
                        "delete" -> result.success(deleteEntry(call.argument<String>("name")!!))
                        else -> result.notImplemented()
                    }
                } catch (e: UnsupportedOperationException) {
                    result.error("unsupported", e.message, null)
                } catch (e: SecurityException) {
                    result.error("security", "Storage access denied: ${e.message}", null)
                } catch (e: IOException) {
                    result.error("io", "File operation failed: ${e.message}", null)
                } catch (e: IllegalArgumentException) {
                    result.error("invalid", e.message, null)
                } catch (e: Exception) {
                    // Unexpected exception types must return to Dart instead of
                    // killing the process; keep the full class name visible.
                    Log.e(tag, "Uncaught channel exception", e)
                    result.error("unexpected", "${e.javaClass.name}: ${e.message}", null)
                }
            }
    }

    /// Runs [task] on the background publish executor and delivers the
    /// MethodChannel result on the main thread exactly once, mapping
    /// exceptions to the same error codes as the synchronous handler.
    private fun runPublishInBackground(result: MethodChannel.Result, task: () -> Map<String, Any>) {
        publishExecutor.execute {
            try {
                val value = task()
                deliverResult(result) { result.success(value) }
            } catch (e: UnsupportedOperationException) {
                deliverResult(result) { result.error("unsupported", e.message, null) }
            } catch (e: SecurityException) {
                deliverResult(result) { result.error("security", "Storage access denied: ${e.message}", null) }
            } catch (e: IOException) {
                deliverResult(result) { result.error("io", "File operation failed: ${e.message}", null) }
            } catch (e: IllegalArgumentException) {
                deliverResult(result) { result.error("invalid", e.message, null) }
            } catch (e: Exception) {
                Log.e(tag, "Uncaught channel exception", e)
                deliverResult(result) { result.error("unexpected", "${e.javaClass.name}: ${e.message}", null) }
            }
        }
    }

    /// Replies to the engine only while it still accepts replies; after activity
    /// detach (or a double-reply) the Dart callback is invalid and would throw.
    private fun deliverResult(result: MethodChannel.Result, reply: () -> Unit) {
        mainHandler.post {
            try {
                reply()
            } catch (_: IllegalStateException) {
                // Already replied or engine detached — nothing to deliver.
            } catch (_: RuntimeException) {
                // Engine no longer accepts replies after detach — drop it.
            }
        }
    }

    private fun requireMediaStore() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw UnsupportedOperationException(
                "User-visible Downloads storage requires Android 10 (API 29)+; " +
                    "this device reports API ${Build.VERSION.SDK_INT}."
            )
        }
    }

    private fun storageDirPath(): String {
        requireMediaStore()
        return Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        ).path + File.separator + "zanado"
    }

    /// Inserts a pending MediaStore entry, copies [source] into it, verifies
    /// [expectedSize] when provided, then publishes (IS_PENDING=0).
    /// [deleteSource] must be true only for app-owned staged files
    /// (commitFromPath's `.part`), never for caller-owned sources.
    private fun publishFile(
        displayName: String,
        source: File,
        expectedSize: Long? = null,
        deleteSource: Boolean,
    ): Map<String, Any> {
        requireMediaStore()
        if (displayName.isBlank()) {
            throw IllegalArgumentException("File name must not be blank")
        }
        if (!source.exists()) {
            throw IOException("Source file does not exist: ${source.path}")
        }

        val resolver = contentResolver
        val finalName = resolveUniqueName(displayName)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, finalName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeFor(finalName))
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: run {
                Log.e(tag, "MediaStore insert rejected for \"$finalName\"")
                throw IOException("MediaStore rejected the download entry for \"$finalName\"")
            }

        var written = 0L
        try {
            resolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        out.write(buffer, 0, read)
                        written += read
                    }
                    out.flush()
                }
            } ?: throw IOException("Could not open output stream for \"$finalName\"")

            if (expectedSize != null && written != expectedSize) {
                Log.e(tag, "Size mismatch written=$written expected=$expectedSize")
                throw IOException(
                    "Size mismatch for \"$finalName\": expected $expectedSize, got $written"
                )
            }

            val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, published, null, null)
        } catch (e: Exception) {
            // Never publish a failed/partial write.
            Log.e(tag, "Publish failed during copy/verify/publish", e)
            try { resolver.delete(uri, null, null) } catch (_: Exception) { /* best effort */ }
            throw e
        }

        if (deleteSource) {
            source.delete()
        }

        return mapOf(
            "name" to finalName,
            "size" to written,
            "date" to System.currentTimeMillis()
        )
    }

    /// Lists published (non-pending) entries under Download/zanado/, newest first.
    private fun listEntries(): List<Map<String, Any>> {
        requireMediaStore()
        val entries = mutableListOf<Map<String, Any>>()
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.SIZE,
                MediaStore.MediaColumns.DATE_MODIFIED,
            ),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.IS_PENDING}=0",
            arrayOf(relativePath),
            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
        )?.use { c ->
            while (c.moveToNext()) {
                entries.add(
                    mapOf(
                        "name" to c.getString(0),
                        "size" to c.getLong(1),
                        "date" to c.getLong(2) * 1000,
                    )
                )
            }
        }
        return entries
    }

    private fun deleteEntry(name: String): Boolean {
        requireMediaStore()
        val deleted = contentResolver.delete(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=?",
            arrayOf(relativePath, name),
        )
        return deleted > 0
    }

    /// Resolves a non-colliding name inside Download/zanado/ (both pending and
    /// published entries count), mirroring the Dart `withCopySuffix` pattern:
    /// `photo.jpg` → `photo (1).jpg` → `photo (2).jpg` …
    private fun resolveUniqueName(displayName: String): String {
        val taken = mutableSetOf<String>()
        contentResolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            "${MediaStore.MediaColumns.RELATIVE_PATH}=?",
            arrayOf(relativePath),
            null,
        )?.use { c ->
            while (c.moveToNext()) taken.add(c.getString(0))
        }
        if (!taken.contains(displayName)) return displayName

        val dot = displayName.lastIndexOf('.')
        val base = if (dot > 0) displayName.substring(0, dot) else displayName
        val ext = if (dot > 0) displayName.substring(dot) else ""
        var i = 1
        while (true) {
            val candidate = "$base ($i)$ext"
            if (!taken.contains(candidate)) return candidate
            i++
        }
    }

    private fun mimeFor(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "mp3" -> "audio/mpeg"
        "m4a" -> "audio/mp4"
        "wav" -> "audio/wav"
        "ogg" -> "audio/ogg"
        "mp4" -> "video/mp4"
        "mkv" -> "video/x-matroska"
        "webm" -> "video/webm"
        "mov" -> "video/quicktime"
        "pdf" -> "application/pdf"
        "zip" -> "application/zip"
        "txt" -> "text/plain"
        else -> "application/octet-stream"
    }
}
