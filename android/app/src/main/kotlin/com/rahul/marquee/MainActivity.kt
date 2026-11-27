package com.rahul.marquee

import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var content: ContentChannel? = null
    private var pip: PipChannel? = null
    private var media: MediaChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        content = ContentChannel(applicationContext, messenger).also {
            it.setPendingUri(uriFrom(intent))
            it.activity = this
        }
        pip = PipChannel(this, messenger)
        media = MediaChannel(applicationContext, messenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // The document picker (ContentChannel.pickVideo) answers here.
        if (content?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // Plugins first (they share this callback), then the device library's video permission.
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        content?.onRequestPermissionsResult(requestCode)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // singleTask: an "Open with" from any app while Marquee is running arrives here, in the
        // one running instance, instead of starting a second engine in the caller's task.
        uriFrom(intent)?.let { content?.deliverNewUri(it) }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pip?.onPipChanged(isInPictureInPictureMode)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // API 26–30 have no setAutoEnterEnabled; emulate it when Dart asked for auto-enter.
        pip?.onUserLeaveHint()
    }

    override fun onDestroy() {
        content?.dispose()
        pip?.dispose()
        // The engine dies with this activity: the lock-screen controls and the playback service
        // go with it, or they would point at a film nothing can play.
        media?.dispose()
        content = null
        pip = null
        media = null
        super.onDestroy()
    }

    /** The video a VIEW ("Open with") or SEND (share sheet) intent carries, if any. */
    private fun uriFrom(intent: Intent?): Uri? {
        if (intent == null) return null
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> streamExtra(intent)
            else -> null
        } ?: return null
        if (uri.scheme != "content" && uri.scheme != "file") return null
        if (uri.scheme == "content" &&
            intent.action == Intent.ACTION_VIEW &&
            (intent.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION) != 0
        ) {
            try {
                // The sender offered a grant that outlives this launch: keep it, so the Lobby
                // card can reopen the film after a restart.
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (e: SecurityException) {
                // Offered but not persistable after all: it plays now, the card may not.
            }
        }
        return uri
    }

    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            legacyStreamExtra(intent)
        }

    @Suppress("DEPRECATION")
    private fun legacyStreamExtra(intent: Intent): Uri? =
        intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
}
