import 'dart:async';
import 'package:flutter/services.dart';

/// Flutter-side bridge to the Android [RemoteControlAccessibilityService].
///
/// Communicates via a MethodChannel to:
/// - Check if the Accessibility Service is enabled
/// - Open Android Accessibility Settings for the user to enable it
/// - Enable / disable gesture injection for a session
/// - Dispatch tap, swipe, and global key gestures
class AccessibilityControlService {
  static const _channel = MethodChannel(
    'com.example.remote_access/accessibility',
  );

  // ── Singleton ────────────────────────────────────────────────────────────────

  static final AccessibilityControlService _instance =
      AccessibilityControlService._();
  factory AccessibilityControlService() => _instance;
  AccessibilityControlService._();

  // ── Status ───────────────────────────────────────────────────────────────────

  /// Returns true if the Accessibility Service is enabled in Android settings.
  Future<bool> isEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Opens the Android Accessibility Settings screen so the user can enable
  /// the service manually.
  Future<void> openSettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  // ── Session Control ──────────────────────────────────────────────────────────

  /// Arms the service to accept gesture commands for the current session.
  /// Must be called when a remote control session starts on Device B.
  Future<void> enableControl() async {
    await _channel.invokeMethod('setControlEnabled', {'enabled': true});
  }

  /// Disarms gesture injection when the session ends.
  Future<void> disableControl() async {
    await _channel.invokeMethod('setControlEnabled', {'enabled': false});
  }

  // ── Gesture Injection ─────────────────────────────────────────────────────────

  /// Dispatches a single tap at normalized coordinates [0.0–1.0].
  Future<bool> performTap(double x, double y) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('performTap', {'x': x, 'y': y});
      return result ?? false;
    } on PlatformException catch (e) {
      _handleError('performTap', e);
      return false;
    }
  }

  /// Dispatches a swipe gesture. All coordinates are normalized [0.0–1.0].
  Future<bool> performSwipe({
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    int durationMs = 300,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('performSwipe', {
        'fromX': fromX,
        'fromY': fromY,
        'toX': toX,
        'toY': toY,
        'durationMs': durationMs,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _handleError('performSwipe', e);
      return false;
    }
  }

  /// Dispatches the Android BACK action.
  Future<bool> performBack() async {
    try {
      final result = await _channel.invokeMethod<bool>('performBack');
      return result ?? false;
    } on PlatformException catch (e) {
      _handleError('performBack', e);
      return false;
    }
  }

  /// Dispatches the Android HOME action.
  Future<bool> performHome() async {
    try {
      final result = await _channel.invokeMethod<bool>('performHome');
      return result ?? false;
    } on PlatformException catch (e) {
      _handleError('performHome', e);
      return false;
    }
  }

  /// Dispatches the Android RECENTS action.
  Future<bool> performRecents() async {
    try {
      final result = await _channel.invokeMethod<bool>('performRecents');
      return result ?? false;
    } on PlatformException catch (e) {
      _handleError('performRecents', e);
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _handleError(String method, PlatformException e) {
    // SERVICE_NOT_CONNECTED is expected if the accessibility service hasn't
    // been enabled in system settings yet.
    if (e.code != 'SERVICE_NOT_CONNECTED') {
      // ignore: avoid_print
      print('AccessibilityControlService.$method error: ${e.code} — ${e.message}');
    }
  }
}
