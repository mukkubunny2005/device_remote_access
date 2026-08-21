package com.example.remote_access

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Point
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Phase 5: RemoteControlAccessibilityService
 *
 * Receives gesture/key commands from Flutter via a MethodChannel and dispatches
 * them using Android's AccessibilityService gesture injection API (API 24+).
 *
 * This service MUST be explicitly enabled by the user via:
 * Android Settings → Accessibility → Remote Access → Enable
 *
 * It never monitors content and only dispatches gestures when a verified
 * remote control session is active (controlled via [setControlEnabled]).
 */
class RemoteControlAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "RemoteControlA11y"

        /** Singleton reference used by [MainActivity] to bind the MethodChannel. */
        var instance: RemoteControlAccessibilityService? = null
            private set

        /** Channel name matches the Flutter-side channel registration. */
        const val CHANNEL = "com.example.remote_access/accessibility"

        /** Only process gesture commands when a remote session has been accepted. */
        var controlEnabled: Boolean = false

        /** Screen dimensions (updated on service connect). */
        var screenWidth: Int = 1080
        var screenHeight: Int = 1920
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        updateScreenDimensions()
        Log.i(TAG, "Accessibility service connected — screen: ${screenWidth}x${screenHeight}")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        controlEnabled = false
        Log.i(TAG, "Accessibility service unbound.")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        controlEnabled = false
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We do not process accessibility events — read-access is intentionally disabled.
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted.")
    }

    // ── Gesture Injection ──────────────────────────────────────────────────────

    /**
     * Dispatches a single tap at the given (normalizedX, normalizedY) coordinates.
     * Coordinates are in the range [0.0, 1.0] relative to screen dimensions.
     */
    fun performTap(normalizedX: Float, normalizedY: Float): Boolean {
        if (!controlEnabled) {
            Log.w(TAG, "performTap blocked — control not enabled.")
            return false
        }
        val px = (normalizedX * screenWidth).toInt().coerceIn(0, screenWidth - 1)
        val py = (normalizedY * screenHeight).toInt().coerceIn(0, screenHeight - 1)
        Log.d(TAG, "performTap: ($px, $py)")

        val path = Path().apply { moveTo(px.toFloat(), py.toFloat()) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 100L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    /**
     * Dispatches a swipe/drag gesture from start to end.
     */
    fun performSwipe(
        fromX: Float, fromY: Float,
        toX: Float, toY: Float,
        durationMs: Long = 300L
    ): Boolean {
        if (!controlEnabled) {
            Log.w(TAG, "performSwipe blocked — control not enabled.")
            return false
        }
        val startPx = (fromX * screenWidth).toInt().coerceIn(0, screenWidth - 1)
        val startPy = (fromY * screenHeight).toInt().coerceIn(0, screenHeight - 1)
        val endPx = (toX * screenWidth).toInt().coerceIn(0, screenWidth - 1)
        val endPy = (toY * screenHeight).toInt().coerceIn(0, screenHeight - 1)

        Log.d(TAG, "performSwipe: ($startPx,$startPy) → ($endPx,$endPy) in ${durationMs}ms")

        val path = Path().apply {
            moveTo(startPx.toFloat(), startPy.toFloat())
            lineTo(endPx.toFloat(), endPy.toFloat())
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    /**
     * Presses the Android BACK button.
     */
    fun performBack(): Boolean {
        if (!controlEnabled) return false
        Log.d(TAG, "performBack")
        return performGlobalAction(GLOBAL_ACTION_BACK)
    }

    /**
     * Presses the Android HOME button.
     */
    fun performHome(): Boolean {
        if (!controlEnabled) return false
        Log.d(TAG, "performHome")
        return performGlobalAction(GLOBAL_ACTION_HOME)
    }

    /**
     * Opens the recents/overview screen.
     */
    fun performRecents(): Boolean {
        if (!controlEnabled) return false
        Log.d(TAG, "performRecents")
        return performGlobalAction(GLOBAL_ACTION_RECENTS)
    }

    // ── Screen Dimensions ──────────────────────────────────────────────────────

    private fun updateScreenDimensions() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            screenWidth = bounds.width()
            screenHeight = bounds.height()
        } else {
            @Suppress("DEPRECATION")
            val size = Point()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getSize(size)
            screenWidth = size.x
            screenHeight = size.y
        }
    }
}
