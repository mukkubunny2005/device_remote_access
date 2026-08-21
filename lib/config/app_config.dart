// Application configuration.
//
// Edit baseUrl for your environment:
//   - Android Emulator → http://10.0.2.2:8000
//   - Physical device  → http://<your-LAN-IP>:8000
//   - Production       → https://api.your-domain.com

class AppConfig {
  AppConfig._();

  // ── Backend URL ────────────────────────────────────────────────────────────
  /// Base URL for the FastAPI backend.
  /// Change to your LAN IP when testing on a physical device.
  static const String baseUrl = 'http://10.0.2.2:8000';

  // ── App ────────────────────────────────────────────────────────────────────
  static const String appName = 'Remote Access';
  static const String appVersion = '1.0.0';

  // ── Timeouts ───────────────────────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // ── Storage keys ───────────────────────────────────────────────────────────
  static const String kDeviceId = 'device_id';
  static const String kDeviceName = 'device_name';
  static const String kAccessToken = 'access_token';
  static const String kRefreshToken = 'refresh_token';

  // ── WebSocket heartbeat ────────────────────────────────────────────────────
  static const Duration wsHeartbeatInterval = Duration(seconds: 25);
}
