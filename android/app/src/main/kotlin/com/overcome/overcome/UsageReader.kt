package com.overcome.overcome

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Process
import java.io.ByteArrayOutputStream
import java.util.Calendar

/**
 * Computes real device usage from the system's UsageEvents log (requires the
 * user to grant "Usage access"). Foreground time is reconstructed from
 * resume/pause pairs, which is more accurate than UsageStats buckets.
 */
object UsageReader {
    data class AppUsage(val pkg: String, var foregroundMs: Long = 0, var launches: Int = 0)

    data class Summary(
        val apps: Map<String, AppUsage>,
        val pickups: Int,
        val screenOnMs: Long,
        val hourlyMs: LongArray,
        val totalMs: Long,
    )

    data class Session(val pkg: String, val sinceMs: Long)

    // Event type constants (some are API 28+; numeric values are stable).
    private const val RESUMED = 1 // ACTIVITY_RESUMED / MOVE_TO_FOREGROUND
    private const val PAUSED = 2 // ACTIVITY_PAUSED / MOVE_TO_BACKGROUND
    private const val STOPPED = 23 // ACTIVITY_STOPPED
    private const val SCREEN_INTERACTIVE = 15
    private const val SCREEN_NON_INTERACTIVE = 16
    private const val KEYGUARD_HIDDEN = 18

    fun hasAccess(ctx: Context): Boolean {
        val ops = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), ctx.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun startOfDay(dayOffset: Int = 0): Long = Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, dayOffset)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /** Launchers and system UI are "the phone itself", not app usage. */
    private fun ignoredPackages(ctx: Context): Set<String> {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val launchers = ctx.packageManager.queryIntentActivities(home, PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo.packageName }
        return (launchers + listOf("com.android.systemui", "android")).toSet()
    }

    fun summary(ctx: Context, start: Long, end: Long): Summary {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val ignored = ignoredPackages(ctx)
        val events = usm.queryEvents(start, end)
        val apps = HashMap<String, AppUsage>()
        val hourly = LongArray(24)
        val openSince = HashMap<String, Long>()
        var lastForeground: String? = null
        var pickups = 0
        var screenOnSince: Long? = null
        var screenOnMs = 0L
        val e = UsageEvents.Event()

        fun credit(pkg: String, from: Long, to: Long) {
            if (to <= from) return
            apps.getOrPut(pkg) { AppUsage(pkg) }.foregroundMs += to - from
            addHourly(hourly, from, to)
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val pkg = e.packageName
            val t = e.timeStamp
            when (e.eventType) {
                RESUMED -> if (pkg !in ignored) {
                    if (!openSince.containsKey(pkg)) openSince[pkg] = t
                    if (pkg != lastForeground) apps.getOrPut(pkg) { AppUsage(pkg) }.launches++
                    lastForeground = pkg
                }
                PAUSED, STOPPED -> openSince.remove(pkg)?.let { credit(pkg, it, t) }
                SCREEN_INTERACTIVE -> screenOnSince = t
                SCREEN_NON_INTERACTIVE -> {
                    screenOnSince?.let { screenOnMs += t - it }
                    screenOnSince = null
                    // Screen off ends every foreground session.
                    for ((p, since) in openSince) credit(p, since, t)
                    openSince.clear()
                    lastForeground = null
                }
                KEYGUARD_HIDDEN -> pickups++
            }
        }
        // Sessions still running at the end of the window.
        val now = minOf(end, System.currentTimeMillis())
        for ((p, since) in openSince) credit(p, since, now)
        screenOnSince?.let { screenOnMs += now - it }

        return Summary(apps, pickups, screenOnMs, hourly, apps.values.sumOf { it.foregroundMs })
    }

    /** The app in the foreground right now and when its session began. */
    fun currentSession(ctx: Context): Session? {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val events = usm.queryEvents(now - 3 * 3600_000L, now)
        val ignored = ignoredPackages(ctx)
        val e = UsageEvents.Event()
        var current: Session? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            when (e.eventType) {
                RESUMED -> current = if (e.packageName in ignored) null
                else if (current?.pkg == e.packageName) current else Session(e.packageName, e.timeStamp)
                PAUSED, STOPPED -> if (current?.pkg == e.packageName) current = null
                SCREEN_NON_INTERACTIVE -> current = null
            }
        }
        return current
    }

    /** Unlocks in the trailing window — a strong compulsion signal. */
    fun pickupsSince(ctx: Context, since: Long): Int {
        val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(since, System.currentTimeMillis())
        val e = UsageEvents.Event()
        var n = 0
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == KEYGUARD_HIDDEN) n++
        }
        return n
    }

    private fun addHourly(hourly: LongArray, from: Long, to: Long) {
        val cal = Calendar.getInstance()
        var t = from
        while (t < to) {
            cal.timeInMillis = t
            val hour = cal.get(Calendar.HOUR_OF_DAY)
            cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0)
            cal.set(Calendar.MILLISECOND, 0)
            val nextHour = cal.timeInMillis + 3600_000L
            val chunkEnd = minOf(to, nextHour)
            hourly[hour] += chunkEnd - t
            t = chunkEnd
        }
    }

    private val labels = HashMap<String, String>()
    private val icons = HashMap<String, ByteArray>()

    fun label(ctx: Context, pkg: String): String = labels.getOrPut(pkg) {
        try {
            val pm = ctx.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            pkg.substringAfterLast('.').replaceFirstChar { it.uppercase() }
        }
    }

    /** 96px PNG of the app icon, cached in memory. */
    fun icon(ctx: Context, pkg: String): ByteArray? = icons[pkg] ?: try {
        val d = ctx.packageManager.getApplicationIcon(pkg)
        val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, 96, 96)
        d.draw(c)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        out.toByteArray().also { icons[pkg] = it }
    } catch (_: Exception) {
        null
    }
}
