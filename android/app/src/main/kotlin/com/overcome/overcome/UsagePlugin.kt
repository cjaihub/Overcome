package com.overcome.overcome

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Dart bridge for usage tracking and Guardian mode (`ovacome/usage`). */
class UsagePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context
    private val io = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ovacome/usage")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf(
                    "usageAccess" to UsageReader.hasAccess(ctx),
                    "notificationAccess" to NotificationCounter.isEnabled(ctx),
                    "guardianEnabled" to GuardianConfig.load(ctx).enabled,
                ),
            )
            "openUsageAccessSettings" -> openSettings(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:${ctx.packageName}")),
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
                result,
            )
            "openNotificationAccessSettings" -> openSettings(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
                null,
                result,
            )
            // Usage queries walk the event log, so they run off the UI thread.
            "summary" -> background(result) { summary(call) }
            "current" -> background(result) {
                UsageReader.currentSession(ctx)?.let {
                    mapOf("package" to it.pkg, "label" to UsageReader.label(ctx, it.pkg), "since" to it.sinceMs)
                }
            }
            "configureGuardian" -> {
                val json = call.argument<String>("config")!!
                GuardianConfig.save(ctx, json)
                if (GuardianConfig.load(ctx).enabled) GuardianService.start(ctx) else GuardianService.stop(ctx)
                result.success(null)
            }
            "drainNudges" -> result.success(GuardianConfig.drainNudges(ctx))
            else -> result.notImplemented()
        }
    }

    private fun summary(call: MethodCall): Map<String, Any?> {
        val start = call.argument<Number>("start")!!.toLong()
        val end = call.argument<Number>("end")!!.toLong()
        val withIcons = call.argument<Boolean>("icons") ?: false
        val s = UsageReader.summary(ctx, start, end)
        val notif = NotificationCounter.day(ctx, NotificationCounter.dayKey(start))
        val notifApps = notif.optJSONObject("apps")
        val notifHours = notif.optJSONArray("hours")
        val apps = s.apps.values.sortedByDescending { it.foregroundMs }.take(30).map { a ->
            mapOf(
                "package" to a.pkg,
                "label" to UsageReader.label(ctx, a.pkg),
                "foregroundMs" to a.foregroundMs,
                "launches" to a.launches,
                "notifications" to (notifApps?.optInt(a.pkg) ?: 0),
                "icon" to if (withIcons) UsageReader.icon(ctx, a.pkg) else null,
            )
        }
        return mapOf(
            "totalMs" to s.totalMs,
            "screenOnMs" to s.screenOnMs,
            "pickups" to s.pickups,
            "notifications" to notif.optInt("total"),
            "hourlyMs" to s.hourlyMs.toList(),
            "hourlyNotifications" to (0 until 24).map { notifHours?.optInt(it) ?: 0 },
            "apps" to apps,
        )
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val out = try {
                Result.success(work())
            } catch (e: Exception) {
                Result.failure(e)
            }
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                out.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("usage_error", it.message, null) },
                )
            }
        }
    }

    private fun openSettings(primary: Intent, fallback: Intent?, result: MethodChannel.Result) {
        try {
            ctx.startActivity(primary.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            fallback?.let { ctx.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
        result.success(null)
    }
}

/** Restarts Guardian mode after a reboot if the user had it on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && GuardianConfig.load(context).enabled) {
            GuardianService.start(context)
        }
    }
}
