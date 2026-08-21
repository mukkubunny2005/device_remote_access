# Remote Access — Flutter Mobile App

> ⚠️ **Consent-first**: Every remote-access session requires **explicit approval** from the target device. Remote access can never start silently.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter + Dart |
| State management | Riverpod (StateNotifier) |
| HTTP client | Dio (JWT injection + auto-refresh) |
| Secure storage | flutter_secure_storage (EncryptedSharedPreferences) |
| Persistent storage | shared_preferences (Device ID) |
| UI | Material 3 · Google Fonts (Inter) · dark theme |

---

## Project Structure

```
lib/
├── main.dart                  ← App entry, ProviderScope, Material 3 theme
├── config/
│   └── app_config.dart        ← Base URL, timeouts, storage keys
├── models/
│   ├── device_model.dart
│   └── user_model.dart
├── services/
│   ├── storage_service.dart   ← SharedPrefs + FlutterSecureStorage
│   ├── api_service.dart       ← Dio client with JWT + refresh
│   ├── auth_service.dart      ← register / login / logout / me
│   └── device_service.dart    ← ID generation + registration
├── providers/
│   ├── auth_provider.dart     ← AuthState (sealed) + StateNotifier
│   └── device_provider.dart   ← DeviceState (sealed) + StateNotifier
├── screens/
│   ├── splash/splash_screen.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   └── home/home_screen.dart
└── widgets/
    ├── device_id_card.dart    ← Premium glassmorphism Device ID display
    └── status_badge.dart      ← Animated online/offline indicator
```

---

## Quick Start

### 1. Install Flutter dependencies

```bash
flutter pub get
```

### 2. Start the backend

```bash
# In d:\remote_access\backend\
venv\Scripts\activate        # Windows
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 3. Configure base URL

Edit [`lib/config/app_config.dart`](lib/config/app_config.dart):

```dart
// Android Emulator
static const String baseUrl = 'http://10.0.2.2:8000';

// Physical device — replace with your machine's LAN IP:
static const String baseUrl = 'http://192.168.1.x:8000';
```

### 4. Run on Android

```bash
flutter run
```

---

## Android Requirements

| Requirement | Value |
|-------------|-------|
| Minimum SDK | 26 (Android 8.0) |
| Target SDK | Latest via flutter.targetSdkVersion |

**Reason for minSdk 26:**
- `flutter_secure_storage` uses `EncryptedSharedPreferences` (API 23+, best at 26+)
- `MediaProjection` foreground service type (Phase 4, API 29+)

---

## Permissions (Phase 1)

| Permission | Why |
|------------|-----|
| `INTERNET` | Backend API + WebSocket |
| `ACCESS_NETWORK_STATE` | Connectivity check |
| `POST_NOTIFICATIONS` | Reserved for FCM (Phase 3) |
| `FOREGROUND_SERVICE` | Reserved for screen sharing (Phase 4) |

---

## Device ID System

- Generated once using `Random.secure()` — **no IMEI, MAC, or hardware identifiers**
- Stored in `SharedPreferences` — survives app restarts
- Registered with the backend on every launch (upsert — safe to call repeatedly)
- Displayed as `XXXX XXXX` for readability; transmitted as `XXXXXXXX`
- An 8-digit ID alone **never** authorizes remote access

---

## Phase Roadmap

| Phase | Status | Features |
|-------|--------|----------|
| 1 | ✅ Done | Auth, Device ID, Registration, Status |
| 2 | 🔜 | Pairing system |
| 3 | 🔜 | Access requests, FCM, WebSocket |
| 4 | 🔜 | MediaProjection, WebRTC, Screen sharing |
| 5 | 🔜 | AccessibilityService, Remote control |
| 6 | 🔜 | PostgreSQL, Docker, CI/CD |

---

## Running Tests

```bash
flutter test
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Connection refused` | Ensure backend is running; check `baseUrl` |
| `CLEARTEXT communication not permitted` | Set `baseUrl` to `https://` or keep `usesCleartextTraffic` for dev |
| `minSdkVersion` error | Emulator/device must be API 26+ |
| Token expired on launch | App auto-refreshes tokens via Dio interceptor |
