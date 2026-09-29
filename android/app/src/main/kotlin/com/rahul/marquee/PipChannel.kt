package com.rahul.marquee

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `marquee/pip` — picture-in-picture without a plugin.
 *
 *   enter        {w, h}           -> Boolean  (false when PiP is unsupported or refused);
 *                                              also turns auto-enter on
 *   setAutoEnter {enabled, w, h}  -> Boolean  (API 31+: setAutoEnterEnabled; 26–30: emulated on
 *                                              onUserLeaveHint by MainActivity)
 *   isSupported                   -> Boolean
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

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
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
    }

    private fun isSupported(): Boolean =
        activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun params(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect(lastW, lastH))
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
