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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        content = ContentChannel(applicationContext, messenger).also {
            it.setPendingUri(uriFrom(intent))
        }
        pip = PipChannel(this, messenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // singleTop: a second "Open with" while running arrives here instead of a new Activity.
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
        content = null
        pip = null
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
        return if (uri.scheme == "content" || uri.scheme == "file") uri else null
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
