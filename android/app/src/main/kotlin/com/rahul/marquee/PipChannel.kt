package com.rahul.marquee

import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `marquee/pip` — picture-in-picture without a plugin.
 *
 *   enter        {w, h, playing}           -> Boolean  (false when PiP is unsupported or refused);
 *                                                       also turns auto-enter on
 *   setAutoEnter {enabled, w, h, playing}  -> Boolean  (API 31+: setAutoEnterEnabled; 26–30:
 *                                                       emulated on onUserLeaveHint by MainActivity)
 *   isSupported                            -> Boolean
 *
 * w × h is the picture's own size, so the PiP window has the film's shape. The PiP window
 * carries one play / pause action; tapping it sends `pipAction` "playPause" to Dart.
 *
 * Native -> Dart: `pipChanged` {inPip: Boolean}, so the UI drops ALL chrome while in PiP.
 */
class PipChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, NAME)
    private var autoEnter = false
    private var lastW = 16
    private var lastH = 9
    private var playing = true

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ACTION_PLAY_PAUSE) return
            playing = !playing
            applyParams() // flip the icon now; Dart confirms the real state a moment later
            channel.invokeMethod("pipAction", "playPause")
        }
    }

    init {
        channel.setMethodCallHandler(this)
        registerReceiver()
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun registerReceiver() {
        val filter = IntentFilter(ACTION_PLAY_PAUSE)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
        } catch (e: RuntimeException) {
            // No action button then; PiP itself still works.
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        try {
            activity.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Never registered.
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "enter" -> {
                remember(call)
                // Entering by hand means a film is playing: from here on, Home also enters PiP
                // (spec §8.2) until Dart turns it off with setAutoEnter {enabled: false}.
                autoEnter = true
                result.success(enter())
            }
            "setAutoEnter" -> {
                remember(call)
                autoEnter = call.argument<Boolean>("enabled") ?: false
                result.success(applyParams())
            }
            else -> result.notImplemented()
        }
    }

    fun onPipChanged(inPip: Boolean) {
        channel.invokeMethod("pipChanged", mapOf("inPip" to inPip))
    }

    /** Called from MainActivity.onUserLeaveHint (Home / Recents while a film is playing). */
    fun onUserLeaveHint() {
        if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enter()
    }

    private fun remember(call: MethodCall) {
        val w = call.argument<Number>("w")?.toInt()
        val h = call.argument<Number>("h")?.toInt()
        if (w != null && h != null && w > 0 && h > 0) {
            lastW = w
            lastH = h
        }
        call.argument<Boolean>("playing")?.let { playing = it }
    }

    private fun isSupported(): Boolean =
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun playPauseAction(): RemoteAction {
        val intent = Intent(ACTION_PLAY_PAUSE).setPackage(activity.packageName)
        val pending = PendingIntent.getBroadcast(
            activity,
            REQUEST_PLAY_PAUSE,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val title = if (playing) "Pause" else "Play"
        val icon = Icon.createWithResource(
            activity,
            if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
        )
        return RemoteAction(icon, title, title, pending)
    }

    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(aspect(lastW, lastH))
            .setActions(listOf(playPauseAction()))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun enter(): Boolean {
        if (!isSupported()) return false
        return try {
            activity.enterPictureInPictureMode(params())
        } catch (e: IllegalStateException) {
            false
        } catch (e: IllegalArgumentException) {
            false
        }
    }

    private fun applyParams(): Boolean {
        if (!isSupported()) return false
        return try {
            activity.setPictureInPictureParams(params())
            true
        } catch (e: IllegalStateException) {
            false
        } catch (e: IllegalArgumentException) {
            false
        }
    }

    private companion object {
        const val NAME = "marquee/pip"
        const val ACTION_PLAY_PAUSE = "com.rahul.marquee.PIP_PLAY_PAUSE"
        const val REQUEST_PLAY_PAUSE = 0x5050

        // Android rejects PiP aspect ratios outside 1:2.39 .. 2.39:1.
        val WIDEST = Rational(239, 100)
        val TALLEST = Rational(100, 239)

        fun aspect(w: Int, h: Int): Rational {
            if (w <= 0 || h <= 0) return Rational(16, 9)
            val r = w.toDouble() / h.toDouble()
            return when {
                r > WIDEST.toDouble() -> WIDEST
                r < TALLEST.toDouble() -> TALLEST
                else -> Rational(w, h)
            }
        }
    }
}
