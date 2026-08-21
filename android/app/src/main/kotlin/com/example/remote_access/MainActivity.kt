package com.example.remote_access

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Phase 5: MainActivity extends FlutterActivity and wires up the
 * MethodChannel for bidirectional communication with the Accessibility service.
 */
class MainActivity : FlutterActivity() {

    private val channel = RemoteControlAccessibilityService.CHANNEL

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ── Accessibility Status ─────────────────────────────────
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }

                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }

                    // ── Session Control ──────────────────────────────────────
                    "setControlEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        RemoteControlAccessibilityService.controlEnabled = enabled
                        Log.i("MainActivity", "Remote control enabled=$enabled")
                        result.success(null)
                    }

                    // ── Gesture Injection ────────────────────────────────────
                    "performTap" -> {
                        val x = call.argument<Double>("x")?.toFloat() ?: 0f
                        val y = call.argument<Double>("y")?.toFloat() ?: 0f
                        val svc = RemoteControlAccessibilityService.instance
                        if (svc == null) {
                            result.error("SERVICE_NOT_CONNECTED",
                                "Accessibility service not running", null)
                        } else {
                            result.success(svc.performTap(x, y))
                        }
                    }

                    "performSwipe" -> {
                        val fromX = call.argument<Double>("fromX")?.toFloat() ?: 0f
                        val fromY = call.argument<Double>("fromY")?.toFloat() ?: 0f
                        val toX   = call.argument<Double>("toX")?.toFloat()   ?: 0f
                        val toY   = call.argument<Double>("toY")?.toFloat()   ?: 0f
                        val dur   = call.argument<Long>("durationMs") ?: 300L
                        val svc   = RemoteControlAccessibilityService.instance
                        if (svc == null) {
                            result.error("SERVICE_NOT_CONNECTED",
                                "Accessibility service not running", null)
                        } else {
                            result.success(svc.performSwipe(fromX, fromY, toX, toY, dur))
                        }
                    }

                    "performBack" -> {
                        val svc = RemoteControlAccessibilityService.instance
                        result.success(svc?.performBack() ?: false)
                    }

                    "performHome" -> {
                        val svc = RemoteControlAccessibilityService.instance
                        result.success(svc?.performHome() ?: false)
                    }

                    "performRecents" -> {
                        val svc = RemoteControlAccessibilityService.instance
                        result.success(svc?.performRecents() ?: false)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Accessibility Check ────────────────────────────────────────────────────

    private fun isAccessibilityServiceEnabled(): Boolean {
        val service = "${packageName}/${RemoteControlAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            if (colonSplitter.next().equals(service, ignoreCase = true)) return true
        }
        return false
    }
}
