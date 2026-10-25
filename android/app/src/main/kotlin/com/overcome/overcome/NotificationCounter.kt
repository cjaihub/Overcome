package com.overcome.overcome

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Counts how many notifications each app posts per day and per hour, to show
 * how much the phone pulls for attention. Privacy by design: only the
 * package name and time are recorded — never titles, text or senders.
 */
class NotificationCounter : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val n = sbn.notification
        if (sbn.packageName == packageName) return
        if (sbn.isOngoing || n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        record(this, sbn.packageName, sbn.postTime)
    }

    companion object {
        private const val PREFS = "ovacome_notifications"
        private val dayFmt = SimpleDateFormat("yyyyMMdd", Locale.US)

        fun dayKey(ms: Long = System.currentTimeMillis()): String = dayFmt.format(Date(ms))

        @Synchronized
        fun record(ctx: Context, pkg: String, at: Long) {
            val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val key = dayKey(at)
            val day = JSONObject(prefs.getString(key, "{}")!!)
            val byApp = day.optJSONObject("apps") ?: JSONObject()
            byApp.put(pkg, byApp.optInt(pkg) + 1)
            val hours = day.optJSONArray("hours") ?: org.json.JSONArray(IntArray(24).toList())
            val hour = java.util.Calendar.getInstance().apply { timeInMillis = at }.get(java.util.Calendar.HOUR_OF_DAY)
            hours.put(hour, hours.optInt(hour) + 1)
            day.put("apps", byApp).put("hours", hours).put("total", day.optInt("total") + 1)
            val edit = prefs.edit().putString(key, day.toString())
            // Keep 14 days.
            prefs.all.keys.filter { it < dayKey(at - 14 * 86_400_000L) }.forEach { edit.remove(it) }
            edit.apply()
        }

        fun day(ctx: Context, key: String = dayKey()): JSONObject =
            JSONObject(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(key, "{}")!!)

        fun isEnabled(ctx: Context): Boolean {
            val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: return false
            val me = ComponentName(ctx, NotificationCounter::class.java).flattenToString()
            return flat.split(':').any { it == me }
        }
    }
}
