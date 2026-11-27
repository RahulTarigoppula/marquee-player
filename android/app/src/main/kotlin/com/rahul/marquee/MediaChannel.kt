package com.rahul.marquee

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `marquee/media` — the lock screen, the notification shade and headset buttons, without a
 * plugin.
 *
 *   update {title, subtitle?, durationMs, positionMs, speed, playing, buffering,
 *           hasPrevious, hasNext, stepSeconds}     the open film, whenever any of it changes
 *   clear                                          the film closed
 *
 * Native -> Dart: `play`, `pause`, `rewind`, `forward`, `previous`, `next`, and `seekTo` with
 * the position in milliseconds. Dart acts and answers with a fresh `update`.
 */
class MediaChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, NAME)

    private val sink: (String, Any?) -> Unit = { method, argument ->
        channel.invokeMethod(method, argument)
    }

    init {
        channel.setMethodCallHandler(this)
        NowPlaying.attach(context, sink)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        NowPlaying.detach(context, sink)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title")
                    if (title == null) {
                        result.error("bad-args", "update needs a title", null)
                        return
                    }
                    NowPlaying.update(
                        context,
                        Film(
                            title = title,
                            subtitle = call.argument<String>("subtitle"),
                            durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L,
                            positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L,
                            speed = call.argument<Number>("speed")?.toFloat() ?: 1f,
                            playing = call.argument<Boolean>("playing") ?: false,
                            buffering = call.argument<Boolean>("buffering") ?: false,
                            hasPrevious = call.argument<Boolean>("hasPrevious") ?: false,
                            hasNext = call.argument<Boolean>("hasNext") ?: false,
                            stepSeconds = call.argument<Number>("stepSeconds")?.toInt() ?: 10,
                        ),
                    )
                    result.success(null)
                }
                "clear" -> {
                    NowPlaying.clear(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: RuntimeException) {
            // A device that refuses a session or a service: the film plays without them.
            result.error("media", e.message, null)
        }
    }

    private companion object {
        const val NAME = "marquee/media"
    }
}
