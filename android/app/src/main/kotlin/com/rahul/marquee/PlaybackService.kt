package com.rahul.marquee

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the process in the foreground while a film plays, so Android does not stop the sound
 * when the screen goes off or another app is in front. It owns nothing: [NowPlaying] holds the
 * session and the film, this only carries the notification.
 *
 *   playing  -> foreground, the notification cannot be swiped away
 *   paused   -> an ordinary notification (the service may then be stopped by the system)
 *   no film  -> gone, and the notification with it
 *
 * `android:stopWithTask="true"`: swiping Marquee out of Recents ends the service, and Android
 * then ends the process as it always did. Nothing plays on with no app behind it.
 *
 * The notification's buttons start this service with their action; it hands them to Dart.
 */
class PlaybackService : Service() {
    private var foreground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_SHOW) {
            starting = false
            // Started with startForegroundService: Android requires startForeground in reply,
            // whatever has happened to the film since. sync() below corrects it at once.
            enterForeground(NowPlaying.notification(this) ?: NowPlaying.placeholder(this))
        } else if (action != null) {
            NowPlaying.command(action)
        }
        sync()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        foreground = false
        super.onDestroy()
    }

    /** Matches the service to the film: foreground while it plays, gone when it closes. */
    fun sync() {
        // Created, but onStartCommand has not answered startForegroundService yet: stopping
        // now would be a crash ("did not then call startForeground"). The pending start reads
        // the film as it is when it arrives.
        if (starting) return
        val film = NowPlaying.film
        val n = NowPlaying.notification(this)
        if (film == null || n == null) {
            quit()
            return
        }
        if (film.playing) {
            enterForeground(n)
        } else {
            if (foreground) {
                stopForeground(STOP_FOREGROUND_DETACH)
                foreground = false
            }
            NowPlaying.post(this)
        }
    }

    private fun enterForeground(n: Notification) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NowPlaying.NOTIFICATION_ID,
                    n,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(NowPlaying.NOTIFICATION_ID, n)
            }
            foreground = true
        } catch (e: RuntimeException) {
            // Android 12+ refused a start from the background: the film still plays for as
            // long as the process lives, with an ordinary notification.
            foreground = false
            NowPlaying.post(this)
        }
    }

    private fun quit() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        foreground = false
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(NowPlaying.NOTIFICATION_ID)
        stopSelf()
    }

    companion object {
        private const val ACTION_SHOW = "com.rahul.marquee.media.SHOW"

        private var instance: PlaybackService? = null

        /** startForegroundService has been called and onStartCommand has not answered yet. */
        private var starting = false

        /**
         * The film changed. A running service adjusts itself; a playing film with no service
         * starts one; a paused film needs only its notification.
         */
        fun show(context: Context, playing: Boolean) {
            val running = instance
            if (running != null) {
                running.sync()
                return
            }
            // The pending start reads the film as it is when it arrives.
            if (starting) return
            if (!playing) {
                NowPlaying.post(context)
                return
            }
            try {
                context.startForegroundService(
                    Intent(context, PlaybackService::class.java).setAction(ACTION_SHOW),
                )
                starting = true
            } catch (e: RuntimeException) {
                // Refused from the background (Android 12+): play on with the notification.
                NowPlaying.post(context)
            }
        }
    }
}
