package com.rahul.marquee

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
 *   pickVideo                           -> {uri, name, size}? (ACTION_OPEN_DOCUMENT; null if cancelled)
 *
 * pickVideo never copies the film: it returns the document's content:// URI and takes a
 * PERSISTABLE read grant, so a Lobby card can reopen the same URI after a restart.
 *
 * The device library (MediaStore; needs the video permission, nothing leaves the device):
 *
 *   videoPermission                     -> "granted" | "partial" | "denied"  (never asks)
 *   requestVideoPermission              -> the same, after the system dialog (one at a time)
 *   scanVideos                          -> List of {uri, name, size, durationMs, width, height,
 *                                          modified (epoch ms), folder, folderPath}
 *   videoThumbnail {uri, width: Int}    -> JPEG ByteArray, or null when there is none
 *   shareVideo {uri, name}              -> opens the system share sheet
 *
 * "partial" is Android 14's "selected photos and videos": MediaStore then lists only those.
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

    /** Set by MainActivity: the picker needs an Activity to start from. */
    var activity: Activity? = null

    /** The Dart call waiting for the picker's answer (one picker at a time). */
    private var pickResult: MethodChannel.Result? = null

    /** The Dart call waiting for the permission dialog's answer (one request at a time). */
    private var permissionResult: MethodChannel.Result? = null

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
        try {
            pickResult?.success(null)
        } catch (e: RuntimeException) {
            // The engine is already gone: nobody is waiting any more.
        }
        pickResult = null
        try {
            permissionResult?.success(videoPermissionState())
        } catch (e: RuntimeException) {
            // As above: the engine is gone.
        }
        permissionResult = null
        activity = null
        io.shutdown()
    }

    private fun pickVideo(result: MethodChannel.Result) {
        val host = activity ?: return result.error("no-activity", "no activity to pick from", null)
        if (pickResult != null) return result.error("busy", "a picker is already open", null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            // Matroska is often typed outside video/* by file managers and cloud providers.
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("video/*", "application/x-matroska", "video/x-matroska"),
            )
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        pickResult = result
        try {
            host.startActivityForResult(intent, PICK_VIDEO)
        } catch (e: ActivityNotFoundException) {
            pickResult = null
            result.error("no-picker", "this device has no document picker", null)
        }
    }

    /** From MainActivity.onActivityResult; true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_VIDEO) return false
        val result = pickResult ?: return true
        pickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            // Survives a restart; without it a Lobby card could never reopen this URI.
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            // A provider that grants no persistable access: it plays now, the card may not.
        }
        background(result) {
            val info = stat(uri)
            mapOf("uri" to uri.toString(), "name" to info["name"], "size" to info["size"])
        }
        return true
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
            "pickVideo" -> pickVideo(result)
            "videoPermission" -> result.success(videoPermissionState())
            "requestVideoPermission" -> requestVideoPermission(result)
            "scanVideos" -> background(result) { scanVideos() }
            "videoThumbnail" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("bad-args", "videoThumbnail needs a uri", null)
                val width = (call.argument<Number>("width")?.toInt() ?: 320).coerceIn(64, 1024)
                background(result) { videoThumbnail(Uri.parse(uri), width) }
            }
            "shareVideo" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("bad-args", "shareVideo needs a uri", null)
                shareVideo(Uri.parse(uri), call.argument<String>("name") ?: "video", result)
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

    // ───────────────────────── the device library (MediaStore) ─────────────────────────

    private fun holds(permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** What MediaStore will show us right now. Never opens a dialog. */
    private fun videoPermissionState(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (holds(Manifest.permission.READ_MEDIA_VIDEO)) return "granted"
            // Android 14+: "Select photos and videos" grants only this one.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                holds(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            ) {
                return "partial"
            }
            return "denied"
        }
        return if (holds(Manifest.permission.READ_EXTERNAL_STORAGE)) "granted" else "denied"
    }

    private fun requestVideoPermission(result: MethodChannel.Result) {
        if (videoPermissionState() == "granted") return result.success("granted")
        val host = activity ?: return result.error("no-activity", "no activity to ask from", null)
        if (permissionResult != null) {
            return result.error("busy", "a permission request is already open", null)
        }
        // On Android 14+ asking for both lets the user choose "all" or "selected"; asking again
        // while access is partial reopens the selection.
        val wanted: Array<String> = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        permissionResult = result
        try {
            host.requestPermissions(wanted, REQUEST_VIDEO)
        } catch (e: RuntimeException) {
            permissionResult = null
            result.error("io", e.message, null)
        }
    }

    /** From MainActivity.onRequestPermissionsResult; true when the request was ours. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_VIDEO) return false
        val result = permissionResult ?: return true
        permissionResult = null
        // Read the state back instead of trusting grantResults: a cancelled dialog delivers an
        // empty array, and "selected videos" is a grant of a different permission.
        result.success(videoPermissionState())
        return true
    }

    private fun text(c: Cursor, column: Int): String? =
        if (column >= 0 && !c.isNull(column)) c.getString(column) else null

    private fun number(c: Cursor, column: Int): Long =
        if (column >= 0 && !c.isNull(column)) c.getLong(column) else 0L

    /** Every video MediaStore lists for us, newest first. Empty without permission. */
    @Suppress("DEPRECATION") // MediaColumns.DATA: the only folder path there is before API 29
    private fun scanVideos(): List<Map<String, Any>> {
        if (videoPermissionState() == "denied") return emptyList()
        val hasRelativePath = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val pathColumn =
            if (hasRelativePath) MediaStore.Video.Media.RELATIVE_PATH else MediaStore.Video.Media.DATA
        val collection: Uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DATE_MODIFIED,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
            pathColumn,
        )
        val out = ArrayList<Map<String, Any>>()
        context.contentResolver.query(
            collection,
            projection,
            null,
            null,
            MediaStore.Video.Media.DATE_MODIFIED + " DESC",
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val nameCol = c.getColumnIndex(MediaStore.Video.Media.DISPLAY_NAME)
            val sizeCol = c.getColumnIndex(MediaStore.Video.Media.SIZE)
            val durationCol = c.getColumnIndex(MediaStore.Video.Media.DURATION)
            val widthCol = c.getColumnIndex(MediaStore.Video.Media.WIDTH)
            val heightCol = c.getColumnIndex(MediaStore.Video.Media.HEIGHT)
            val modifiedCol = c.getColumnIndex(MediaStore.Video.Media.DATE_MODIFIED)
            val addedCol = c.getColumnIndex(MediaStore.Video.Media.DATE_ADDED)
            val bucketCol = c.getColumnIndex(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
            val pathCol = c.getColumnIndex(pathColumn)
            while (out.size < MAX_VIDEOS && c.moveToNext()) {
                val id = c.getLong(idCol)
                val path = text(c, pathCol)
                val folderPath = when {
                    path == null -> ""
                    hasRelativePath -> path.trimEnd('/')
                    else -> File(path).parent ?: ""
                }
                // Both are in SECONDS. A file with no modified time still has an added time.
                val modified = number(c, modifiedCol)
                val seconds = if (modified > 0L) modified else number(c, addedCol)
                out.add(
                    mapOf<String, Any>(
                        "uri" to ContentUris.withAppendedId(collection, id).toString(),
                        "name" to (text(c, nameCol) ?: "video"),
                        "size" to number(c, sizeCol),
                        "durationMs" to number(c, durationCol),
                        "width" to number(c, widthCol),
                        "height" to number(c, heightCol),
                        "modified" to seconds * 1000L,
                        "folder" to (text(c, bucketCol) ?: ""),
                        "folderPath" to folderPath,
                    ),
                )
            }
        }
        return out
    }

    /** The system's own thumbnail as JPEG bytes; null when it has none for this video. */
    private fun videoThumbnail(uri: Uri, width: Int): ByteArray? {
        val bitmap: Bitmap? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.contentResolver.loadThumbnail(uri, Size(width, width * 9 / 16), null)
            } else {
                legacyThumbnail(uri)
            }
        } catch (e: IOException) {
            null // no thumbnail for this file
        } catch (e: RuntimeException) {
            null // access revoked, or not a MediaStore id: the card keeps its title card
        }
        if (bitmap == null) return null
        val out = ByteArrayOutputStream()
        val written = bitmap.compress(Bitmap.CompressFormat.JPEG, 82, out)
        bitmap.recycle()
        return if (written) out.toByteArray() else null
    }

    @Suppress("DEPRECATION") // the only thumbnail API before ContentResolver.loadThumbnail (29)
    private fun legacyThumbnail(uri: Uri): Bitmap? =
        MediaStore.Video.Thumbnails.getThumbnail(
            context.contentResolver,
            ContentUris.parseId(uri),
            MediaStore.Video.Thumbnails.MINI_KIND,
            null,
        )

    private fun shareVideo(uri: Uri, name: String, result: MethodChannel.Result) {
        val host = activity ?: return result.error("no-activity", "no activity to share from", null)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "video/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            // The read grant travels with the ClipData through the chooser to the chosen app.
            clipData = ClipData.newRawUri(name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(send, name).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Marquee accepts shared videos itself; sharing one back to Marquee is no use.
            putExtra(
                Intent.EXTRA_EXCLUDE_COMPONENTS,
                arrayOf(ComponentName(context, MainActivity::class.java)),
            )
        }
        try {
            host.startActivity(chooser)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no-share", "nothing on this device can share a video", null)
        } catch (e: SecurityException) {
            result.error("permission-denied", e.message, null)
        }
    }

    private companion object {
        const val NAME = "marquee/content"
        const val MAX_READ = 16 * 1024 * 1024
        const val PICK_VIDEO = 0x4D51
        const val REQUEST_VIDEO = 0x4D52

        /** A scan stops here (the Dart side caps its lists at the same number). */
        const val MAX_VIDEOS = 20000
    }
}
