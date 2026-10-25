package com.overcome.overcome

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * "Guardian mode": a foreground service that watches usage in real time
 * (every 30 s) and nudges the user — by notification and, if enabled, by
 * voice — based on how they are actually using the phone:
 *  - a continuous session in a tracked app passes the session limit,
 *  - the daily limit for tracked apps is reached,
 *  - tracked-app use during the user's late-night window,
 *  - a burst of unlocks (compulsive checking).
 * Its ongoing notification shows today's live screen time and pickups.
 */
class GuardianService : Service(), TextToSpeech.OnInitListener {
    private val handler = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val tick = object : Runnable {
        override fun run() {
            try {
                evaluate()
            } catch (_: SecurityException) {
                // Usage access revoked: keep the service alive but idle.
            }
            handler.postDelayed(this, POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels()
        tts = TextToSpeech(this, this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = statusNotification("Guardian is on", "Watching for long sessions and late-night use.")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(STATUS_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(STATUS_ID, notification)
        }
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        tts?.shutdown()
        super.onDestroy()
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) tts?.language = Locale.getDefault()
    }

    // ---------- Rules ----------

    private fun evaluate() {
        if (!UsageReader.hasAccess(this)) return
        val cfg = GuardianConfig.load(this)
        val state = getSharedPreferences(STATE, MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val today = UsageReader.summary(this, UsageReader.startOfDay(), now)
        val trackedMs = today.apps.filterKeys { it in cfg.tracked }.values.sumOf { it.foregroundMs }

        nm().notify(
            STATUS_ID,
            statusNotification(
                "Today ${fmt(today.totalMs)} · ${today.pickups} pickups",
                if (cfg.tracked.isEmpty()) "Choose apps to watch in Ovacome." else "Tracked apps: ${fmt(trackedMs)} of ${cfg.dailyLimitMin}m",
            ),
        )
        if (!cfg.enabled) return

        val session = UsageReader.currentSession(this)
        val day = NotificationCounter.dayKey()
        val name = cfg.userName.ifBlank { "Hey" }

        // 1) Long continuous session in a tracked app (repeat every half-limit).
        if (session != null && session.pkg in cfg.tracked) {
            val minutes = ((now - session.sinceMs) / 60_000).toInt()
            val key = "session:${session.pkg}:${session.sinceMs}"
            val lastAt = state.getInt(key, 0)
            val next = if (lastAt == 0) cfg.sessionLimitMin else lastAt + maxOf(5, cfg.sessionLimitMin / 2)
            if (minutes >= next) {
                val app = UsageReader.label(this, session.pkg)
                nudge(cfg, "session", "$minutes minutes on $app", "$name, you've been on $app for $minutes minutes. Take a breath — what do you actually need right now?", "/form/urge_log")
                state.edit().putInt(key, minutes).apply()
            }
        }

        // 2) Daily limit for tracked apps.
        if (trackedMs >= cfg.dailyLimitMin * 60_000L && !state.getBoolean("daily:$day", false)) {
            nudge(cfg, "daily", "Daily limit reached", "$name, you've reached your ${cfg.dailyLimitMin}-minute limit for today. You kept a promise to yourself by noticing.", "/coach")
            state.edit().putBoolean("daily:$day", true).apply()
        }

        // 3) Late-night use of tracked apps (≥ 5 min).
        if (session != null && session.pkg in cfg.tracked && inQuietHours(cfg) && now - session.sinceMs >= 5 * 60_000L) {
            val key = "night:$day:${session.sinceMs}"
            if (!state.getBoolean(key, false)) {
                nudge(cfg, "late_night", "It's late", "$name, it's getting late. Your sleep goal matters more than the next scroll. Want to wind down with a book?", "/library")
                state.edit().putBoolean(key, true).apply()
            }
        }

        // 4) Unlock burst: N pickups in the last hour, at most once an hour.
        val lastBurst = state.getLong("burstAt", 0)
        if (now - lastBurst > 3600_000L) {
            val recent = UsageReader.pickupsSince(this, now - 3600_000L)
            if (recent >= cfg.pickupBurst) {
                nudge(cfg, "pickups", "$recent unlocks this hour", "$name, that's $recent unlocks in the last hour. Notice the urge — you don't have to follow it.", "/form/urge_log")
                state.edit().putLong("burstAt", now).apply()
            }
        }
    }

    private fun inQuietHours(cfg: GuardianConfig): Boolean {
        val h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return if (cfg.quietStart <= cfg.quietEnd) h in cfg.quietStart until cfg.quietEnd
        else h >= cfg.quietStart || h < cfg.quietEnd
    }

    private fun nudge(cfg: GuardianConfig, kind: String, title: String, body: String, route: String) {
        val open = PendingIntent.getActivity(
            this, kind.hashCode(),
            Intent(Intent.ACTION_VIEW, Uri.parse("ovacome://app$route"), this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = Notification.Builder(this, NUDGE_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        nm().notify(kind.hashCode(), n)
        if (cfg.voice && ttsReady && !inCall()) {
            tts?.speak(body, TextToSpeech.QUEUE_FLUSH, null, kind)
        }
        GuardianConfig.logNudge(this, kind, title)
    }

    private fun inCall(): Boolean {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        return am.mode == AudioManager.MODE_IN_CALL || am.mode == AudioManager.MODE_IN_COMMUNICATION
    }

    // ---------- Notifications ----------

    private fun nm() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannels() {
        nm().createNotificationChannel(
            NotificationChannel(STATUS_CHANNEL, "Guardian status", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Live screen time while Guardian mode is on"
            },
        )
        nm().createNotificationChannel(
            NotificationChannel(NUDGE_CHANNEL, "Mindful nudges", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Reminders based on how you're using your phone"
            },
        )
    }

    private fun statusNotification(title: String, text: String): Notification {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(Intent.ACTION_VIEW, Uri.parse("ovacome://app/progress"), this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, STATUS_CHANNEL)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    private fun fmt(ms: Long): String {
        val m = ms / 60_000
        return if (m >= 60) "${m / 60}h ${m % 60}m" else "${m}m"
    }

    companion object {
        private const val POLL_MS = 30_000L
        private const val STATUS_ID = 4201
        private const val STATUS_CHANNEL = "guardian_status"
        private const val NUDGE_CHANNEL = "nudges"
        private const val STATE = "ovacome_guardian_state"

        fun start(ctx: Context) {
            ctx.startForegroundService(Intent(ctx, GuardianService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, GuardianService::class.java))
        }
    }
}

/** Settings written from Dart (Settings → Guardian mode). */
data class GuardianConfig(
    val enabled: Boolean,
    val tracked: Set<String>,
    val sessionLimitMin: Int,
    val dailyLimitMin: Int,
    val quietStart: Int,
    val quietEnd: Int,
    val pickupBurst: Int,
    val voice: Boolean,
    val userName: String,
) {
    companion object {
        private const val PREFS = "ovacome_guardian"

        fun load(ctx: Context): GuardianConfig {
            val j = JSONObject(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("config", "{}")!!)
            val tracked = j.optJSONArray("tracked") ?: JSONArray()
            return GuardianConfig(
                enabled = j.optBoolean("enabled", false),
                tracked = (0 until tracked.length()).map { tracked.getString(it) }.toSet(),
                sessionLimitMin = j.optInt("sessionLimitMin", 20),
                dailyLimitMin = j.optInt("dailyLimitMin", 90),
                quietStart = j.optInt("quietStart", 23),
                quietEnd = j.optInt("quietEnd", 6),
                pickupBurst = j.optInt("pickupBurst", 20),
                voice = j.optBoolean("voice", true),
                userName = j.optString("userName", ""),
            )
        }

        fun save(ctx: Context, json: String) {
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("config", json).apply()
        }

        @Synchronized
        fun logNudge(ctx: Context, kind: String, title: String) {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString("nudges", "[]"))
            log.put(JSONObject().put("kind", kind).put("title", title).put("at", System.currentTimeMillis()))
            prefs.edit().putString("nudges", log.toString()).apply()
        }

        /** Returns and clears nudges not yet synced to the cloud. */
        @Synchronized
        fun drainNudges(ctx: Context): String {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val log = prefs.getString("nudges", "[]")!!
            prefs.edit().putString("nudges", "[]").apply()
            return log
        }
    }
}
