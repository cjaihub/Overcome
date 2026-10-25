package com.overcome.overcome

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * AudioServiceFragmentActivity = background audio (just_audio_background)
 * + FragmentActivity (required by local_auth biometrics).
 */
class MainActivity : AudioServiceFragmentActivity() {
    private var events: EventChannel.EventSink? = null
    private var captureCallback: Any? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE before any content is drawn: screenshots, screen
        // recording, casting to insecure displays and the Recents thumbnail
        // all render black for the entire app.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        purgeRendererCache(includeRenders = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "overcome/security").setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                // FLAG_SECURE already makes captures black; there is no
                // "being recorded" state to report on Android.
                "isCaptured" -> result.success(false)
                "purgeRendererCache" -> {
                    purgeRendererCache()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "overcome/security/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
    }

    override fun onStart() {
        super.onStart()
        // Android 14+: report screenshot attempts (they are already blank).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val cb = Activity.ScreenCaptureCallback { events?.success(mapOf("type" to "screenshot")) }
            registerScreenCaptureCallback(mainExecutor, cb)
            captureCallback = cb
        }
    }

    override fun onStop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            (captureCallback as? Activity.ScreenCaptureCallback)?.let { unregisterScreenCaptureCallback(it) }
            captureCallback = null
        }
        super.onStop()
    }

    override fun onDestroy() {
        purgeRendererCache(includeRenders = true)
        super.onDestroy()
    }

    /**
     * pdfx stages decrypted PDFs in cacheDir because PdfRenderer needs a
     * file descriptor. Unlinking is safe once the renderer has opened it
     * (the descriptor stays valid), so no plaintext copy remains on disk.
     * Rendered page bitmaps are only cleared when no page can be mid-render.
     */
    private fun purgeRendererCache(includeRenders: Boolean = false) {
        cacheDir.listFiles()?.forEach { f ->
            if (f.isFile && f.name.endsWith(".pdf")) f.delete()
        }
        if (includeRenders) File(cacheDir, "pdf_renderer_cache").deleteRecursively()
    }
}
