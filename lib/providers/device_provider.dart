import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_model.dart';
import '../services/device_service.dart';
import '../services/storage_service.dart';

// ── Device state ───────────────────────────────────────────────────────────

sealed class DeviceState {
  const DeviceState();
}

class DeviceLoading extends DeviceState {
  const DeviceLoading();
}

class DeviceReady extends DeviceState {
  final String deviceId;
  final String deviceName;
  final DeviceModel? registeredDevice;

  const DeviceReady({
    required this.deviceId,
    required this.deviceName,
    this.registeredDevice,
  });

  bool get isOnline => registeredDevice?.online ?? false;

  DeviceReady copyWith({
    String? deviceId,
    String? deviceName,
    DeviceModel? registeredDevice,
  }) {
    return DeviceReady(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      registeredDevice: registeredDevice ?? this.registeredDevice,
    );
  }
}

class DeviceError extends DeviceState {
  final String message;
  const DeviceError(this.message);
}

// ── Provider ───────────────────────────────────────────────────────────────

final deviceServiceProvider = Provider<DeviceService>((ref) => DeviceService());

class DeviceNotifier extends StateNotifier<DeviceState> {
  final DeviceService _deviceService;

  DeviceNotifier(this._deviceService) : super(const DeviceLoading());

  /// Initialize device: get/create local ID then register with backend.
  Future<void> initialize() async {
    state = const DeviceLoading();
    try {
      final deviceId = await _deviceService.getOrCreateDeviceId();
      final deviceName = (await StorageService.getDeviceName()) ?? 'My Device';

      state = DeviceReady(deviceId: deviceId, deviceName: deviceName);

      // Register with backend (upsert — safe to call every launch)
      final registered = await _deviceService.registerDevice(
        deviceId: deviceId,
        deviceName: deviceName,
      );

      state = DeviceReady(
        deviceId: deviceId,
        deviceName: deviceName,
        registeredDevice: registered,
      );
    } catch (e) {
      state = DeviceError(e.toString());
    }
  }

  Future<void> refresh() => initialize();

  Future<void> markOffline() async {
    final current = state;
    if (current is DeviceReady) {
      try {
        await _deviceService.updateStatus(current.deviceId, online: false);
      } catch (_) {}
    }
  }
}

final deviceProvider = StateNotifierProvider<DeviceNotifier, DeviceState>((ref) {
  return DeviceNotifier(ref.read(deviceServiceProvider));
});
