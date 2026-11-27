package com.rahul.marquee

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock

/** The open film as the system shows it: on the lock screen, in the shade, on a headset. */
data class Film(
    val title: String,
    val subtitle: String?,
    val durationMs: Long,
    val positionMs: Long,
    val speed: Float,
    val playing: Boolean,
    val buffering: Boolean,
    val hasPrevious: Boolean,
    val hasNext: Boolean,
    val stepSeconds: Int,
)

/**
 * The one media session and its notification. Process-wide, because two things need it and
 * neither owns the other: [MediaChannel] (Dart says what is playing) and [PlaybackService]
 * (keeps the process in the foreground while the film plays unseen).
 *
 * Everything here runs on the main thread: the method channel, the session's callbacks and the
 * service's lifecycle all arrive there.
 *
 * No POST_NOTIFICATIONS permission is declared or asked for. Android 13+ shows a media
 * session's controls (quick settings, lock screen) without it; Android 8-12 grant
 * notifications by default.
 */
object NowPlaying {
    const val NOTIFICATION_ID = 0x4d51
    private const val CHANNEL_ID = "playback"

    // Notification buttons and custom session actions share these names; Dart receives them
    // without the prefix (see [command]).
    const val ACTION_PLAY = "com.rahul.marquee.media.play"
    const val ACTION_PAUSE = "com.rahul.marquee.media.pause"
    const val ACTION_REWIND = "com.rahul.marquee.media.rewind"
    const val ACTION_FORWARD = "com.rahul.marquee.media.forward"
    const val ACTION_PREVIOUS = "com.rahul.marquee.media.previous"
    const val ACTION_NEXT = "com.rahul.marquee.media.next"
    private const val PREFIX = "com.rahul.marquee.media."

    var film: Film? = null
        private set

    private var session: MediaSession? = null
    private var sink: ((String, Any?) -> Unit)? = null
    private var wake: PowerManager.WakeLock? = null

    /**
     * The Flutter engine is up: commands go to [to]. A notification left by a killed run goes.
     * Hand [to] back to [detach]: a new activity can attach before the old one's onDestroy
     * arrives (finish, then a quick relaunch), and the old one must not silence the new.
     */
    fun attach(context: Context, to: (String, Any?) -> Unit) {
        sink = to
        if (film == null) manager(context).cancel(NOTIFICATION_ID)
    }

    /** The Flutter engine behind [from] is going: nothing can play, so nothing may be shown. */
    fun detach(context: Context, from: (String, Any?) -> Unit) {
        if (sink !== from) return
        sink = null
        clear(context)
    }

    fun update(context: Context, next: Film) {
        val app = context.applicationContext
        val s = session ?: open(app)
        val before = film
        film = next
        if (before == null ||
            before.title != next.title ||
            before.subtitle != next.subtitle ||
            before.durationMs != next.durationMs
        ) {
            s.setMetadata(metadata(next))
        }
        s.setPlaybackState(playbackState(next))
        if (!s.isActive) s.isActive = true
        hold(app, next.playing)
        PlaybackService.show(app, next.playing)
    }

    fun clear(context: Context) {
        val app = context.applicationContext
        film = null
        hold(app, false)
        session?.let {
            try {
                it.isActive = false
                it.release()
            } catch (e: RuntimeException) {
                // Already released by the system: nothing left to give back.
            }
        }
        session = null
        manager(app).cancel(NOTIFICATION_ID)
        PlaybackService.show(app, false)
    }

    /** A notification button or a custom session action, by its intent action. */
    fun command(action: String) {
        if (!action.startsWith(PREFIX)) return
        send(action.removePrefix(PREFIX), null)
    }

    private fun send(method: String, argument: Any?) {
        if (film == null) return
        try {
            sink?.invoke(method, argument)
        } catch (e: RuntimeException) {
            // The engine went away between the tap and here.
        }
    }

    /** Posts (or refreshes) the notification without a service: enough while paused. */
    fun post(context: Context) {
        val n = notification(context) ?: return
        try {
            manager(context).notify(NOTIFICATION_ID, n)
        } catch (e: RuntimeException) {
            // A device that refuses it still has the session's own controls.
        }
    }

    // ───────────────────────────── the session ─────────────────────────────

    private fun open(app: Context): MediaSession {
        val s = MediaSession(app, "Marquee")
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = send("play", null)
            override fun onPause() = send("pause", null)

            // "Stop" from a headset or a car means "be quiet": the film stays open, paused.
            override fun onStop() = send("pause", null)
            override fun onSeekTo(pos: Long) = send("seekTo", pos)
            override fun onSkipToNext() = send("next", null)
            override fun onSkipToPrevious() = send("previous", null)
            override fun onFastForward() = send("forward", null)
            override fun onRewind() = send("rewind", null)
            override fun onCustomAction(action: String, extras: Bundle?) = command(action)
        })
        s.setSessionActivity(openApp(app))
        session = s
        return s
    }

    private fun metadata(f: Film): MediaMetadata {
        val b = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, f.title)
            .putString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE, f.title)
            // -1 is "unknown": the system then draws no seek bar (a live stream).
            .putLong(MediaMetadata.METADATA_KEY_DURATION, if (f.durationMs > 0) f.durationMs else -1L)
        if (!f.subtitle.isNullOrEmpty()) {
            b.putString(MediaMetadata.METADATA_KEY_ARTIST, f.subtitle)
            b.putString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE, f.subtitle)
        }
        return b.build()
    }

    private fun playbackState(f: Film): PlaybackState {
        var actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_REWIND or
            PlaybackState.ACTION_FAST_FORWARD
        if (f.durationMs > 0) actions = actions or PlaybackState.ACTION_SEEK_TO
        if (f.hasPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        if (f.hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        val state = when {
            !f.playing -> PlaybackState.STATE_PAUSED
            f.buffering -> PlaybackState.STATE_BUFFERING
            else -> PlaybackState.STATE_PLAYING
        }
        // The system advances the position itself from (position, speed, time): Dart only sends
        // again when the film is somewhere the system would not expect.
        val speed = if (state == PlaybackState.STATE_PLAYING) f.speed else 0f
        return PlaybackState.Builder()
            .setActions(actions)
            .setState(state, f.positionMs, speed, SystemClock.elapsedRealtime())
            // Android 13+ draws its controls from the session, not the notification: the jump
            // buttons only exist there as custom actions.
            .addCustomAction(
                PlaybackState.CustomAction.Builder(
                    ACTION_REWIND,
                    "Back ${f.stepSeconds} seconds",
                    R.drawable.ic_media_rewind,
                ).build(),
            )
            .addCustomAction(
                PlaybackState.CustomAction.Builder(
                    ACTION_FORWARD,
                    "Forward ${f.stepSeconds} seconds",
                    R.drawable.ic_media_forward,
                ).build(),
            )
            .build()
    }

    // ───────────────────────────── the notification ─────────────────────────────

    /** Null when no film is open. */
    fun notification(context: Context): Notification? {
        val f = film ?: return null
        val s = session ?: return null
        val app = context.applicationContext
        channel(app)
        val b = base(app)
            .setContentTitle(f.title)
            .setOngoing(f.playing)
        if (!f.subtitle.isNullOrEmpty()) b.setContentText(f.subtitle)

        // Android 8-12 draw these; 13+ ignores them in favour of the session's own actions.
        var index = 0
        val compact = ArrayList<Int>(3)
        if (f.hasPrevious) {
            b.addAction(action(app, R.drawable.ic_media_previous, "Previous", ACTION_PREVIOUS))
            index++
        }
        b.addAction(
            action(app, R.drawable.ic_media_rewind, "Back ${f.stepSeconds} seconds", ACTION_REWIND),
        )
        compact.add(index++)
        b.addAction(
            if (f.playing) {
                action(app, R.drawable.ic_media_pause, "Pause", ACTION_PAUSE)
            } else {
                action(app, R.drawable.ic_media_play, "Play", ACTION_PLAY)
            },
        )
        compact.add(index++)
        b.addAction(
            action(
                app,
                R.drawable.ic_media_forward,
                "Forward ${f.stepSeconds} seconds",
                ACTION_FORWARD,
            ),
        )
        compact.add(index)
        if (f.hasNext) {
            b.addAction(action(app, R.drawable.ic_media_next, "Next", ACTION_NEXT))
        }
        b.setStyle(
            Notification.MediaStyle()
                .setMediaSession(s.sessionToken)
                .setShowActionsInCompactView(*compact.toIntArray()),
        )
        return b.build()
    }

    /**
     * What a service that was started in the foreground shows when the film closed before it
     * came up: Android insists on a notification even then. It is removed in the same breath.
     */
    fun placeholder(context: Context): Notification {
        val app = context.applicationContext
        channel(app)
        return base(app).setContentTitle("Marquee").build()
    }

    private fun base(app: Context): Notification.Builder =
        Notification.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_marquee)
            .setContentIntent(openApp(app))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)

    private fun action(app: Context, icon: Int, title: String, action: String): Notification.Action {
        val intent = Intent(app, PlaybackService::class.java).setAction(action)
        val pending = PendingIntent.getService(
            app,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Action.Builder(Icon.createWithResource(app, icon), title, pending)
            .build()
    }

    /** Tapping the notification (or the lock-screen card) comes back to the film. */
    private fun openApp(app: Context): PendingIntent {
        val intent = Intent(app, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            app,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun channel(app: Context) {
        val m = manager(app)
        if (m.getNotificationChannel(CHANNEL_ID) != null) return
        // LOW: no sound, no heads-up. It is a remote control, not a message.
        val c = NotificationChannel(CHANNEL_ID, "Now playing", NotificationManager.IMPORTANCE_LOW)
        c.description = "Play, pause and skip while a film is open"
        c.setShowBadge(false)
        c.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        m.createNotificationChannel(c)
    }

    private fun manager(context: Context): NotificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // ───────────────────────────── staying awake ─────────────────────────────

    /**
     * With the screen off nothing else keeps the CPU running: libmpv decodes in this process,
     * and a sleeping CPU is silence. Held only while the film plays.
     */
    private fun hold(app: Context, playing: Boolean) {
        try {
            if (playing) {
                val w = wake ?: (app.getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "marquee:playback")
                    .also {
                        it.setReferenceCounted(false)
                        wake = it
                    }
                // Renewed on every update. Released first: a lock that is not reference
                // counted keeps its FIRST timeout otherwise, however often it is taken again.
                if (w.isHeld) w.release()
                w.acquire(WAKE_LIMIT_MS)
            } else {
                wake?.let { if (it.isHeld) it.release() }
            }
        } catch (e: RuntimeException) {
            // No wake lock: the film still plays while the screen is on.
        }
    }

    private const val WAKE_LIMIT_MS = 6L * 60 * 60 * 1000
}
