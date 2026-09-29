package com.rahul.marquee

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * `marquee/content` — lets Dart hash and name a video it only has a content:// (or file://) URI
 * for: the "Open with" / share-sheet file. Every read is positional and bounded, so the moviehash
 * (two 64 KiB chunks) never streams the whole film. IO runs on one background thread; results are
 * posted back on the main looper, as MethodChannel requires.
 *
 *   initialUri                          -> String?  (the launching URI, then cleared)
 *   stat  {uri}                         -> {name: String, size: Long}   (size -1 if unknown)
 *   read  {uri, offset: Long, length: Int} -> ByteArray of exactly `length` bytes, fewer only at EOF
 *
 * Dart -> is also told `uriChanged` (String) when a new file arrives while the app is running.
 */
class ContentChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, NAME)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var pending: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun setPendingUri(uri: Uri?) {
        pending = uri?.toString()
    }

    fun deliverNewUri(uri: Uri) {
        pending = uri.toString()
        channel.invokeMethod("uriChanged", uri.toString())
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialUri" -> {
                val uri = pending
                pending = null
                result.success(uri)
            }
            "stat" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("bad-args", "stat needs a uri", null)
                background(result) { stat(Uri.parse(uri)) }
            }
            "read" -> {
                val uri = call.argument<String>("uri")
                val offset = call.argument<Number>("offset")?.toLong()
                val length = call.argument<Number>("length")?.toInt()
                if (uri == null || offset == null || length == null || offset < 0 ||
                    length < 0 || length > MAX_READ
                ) {
                    return result.error(
                        "bad-args",
                        "read needs a uri, offset >= 0 and 0 <= length <= $MAX_READ",
                        null,
                    )
                }
                background(result) { read(Uri.parse(uri), offset, length) }
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        try {
            io.execute {
                try {
                    val value = work()
                    main.post { result.success(value) }
                } catch (e: SecurityException) {
                    main.post { result.error("permission-denied", e.message, null) }
                } catch (e: FileNotFoundException) {
                    main.post { result.error("not-found", e.message, null) }
                } catch (e: IOException) {
                    main.post { result.error("io", e.message, null) }
                } catch (e: RuntimeException) {
                    main.post { result.error("io", e.message, null) }
                }
            }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            result.error("disposed", "the content channel has been disposed", null)
        }
    }

    private fun stat(uri: Uri): Map<String, Any> {
        if (uri.scheme == "file") {
            val file = File(uri.path ?: throw FileNotFoundException("no path in $uri"))
            if (!file.isFile) throw FileNotFoundException("no file at $uri")
            return mapOf("name" to file.name, "size" to file.length())
        }
        val resolver = context.contentResolver
        var name: String? = null
        var size = -1L
        resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { c ->
            if (c.moveToFirst()) {
                val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (ni >= 0 && !c.isNull(ni)) name = c.getString(ni)
                val si = c.getColumnIndex(OpenableColumns.SIZE)
                if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
            }
        }
        if (size < 0) {
            // Some providers leave SIZE null; the descriptor usually knows.
            resolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                if (afd.length >= 0) size = afd.length
            }
        }
        return mapOf("name" to (name ?: uri.lastPathSegment ?: "video"), "size" to size)
    }

    private fun open(uri: Uri): ParcelFileDescriptor =
        if (uri.scheme == "file") {
            ParcelFileDescriptor.open(
                File(uri.path ?: throw FileNotFoundException("no path in $uri")),
                ParcelFileDescriptor.MODE_READ_ONLY,
            )
        } else {
            context.contentResolver.openFileDescriptor(uri, "r")
                ?: throw FileNotFoundException("the provider returned no descriptor for $uri")
        }

    private fun read(uri: Uri, offset: Long, length: Int): ByteArray {
        if (length == 0) return ByteArray(0)
        open(uri).use { pfd ->
            FileInputStream(pfd.fileDescriptor).use { input ->
                val ch = input.channel
                try {
                    ch.position(offset)
                } catch (e: IOException) {
                    // Not seekable (a pipe from a streaming provider): skip forward instead.
                    var toSkip = offset
                    while (toSkip > 0) {
                        val skipped = input.skip(toSkip)
                        if (skipped <= 0) {
                            if (input.read() < 0) return ByteArray(0)
                            toSkip -= 1
                        } else {
                            toSkip -= skipped
                        }
                    }
                }
                val buf = ByteBuffer.allocate(length)
                while (buf.hasRemaining()) {
                    if (ch.read(buf) < 0) break
                }
                val got = buf.position()
                return if (got == length) buf.array() else buf.array().copyOf(got)
            }
        }
    }

    private companion object {
        const val NAME = "marquee/content"
        const val MAX_READ = 16 * 1024 * 1024
    }
}
