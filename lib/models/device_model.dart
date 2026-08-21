/// Device data model mirroring the backend Device schema.
class DeviceModel {
  final String id;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? appVersion;
  final bool online;
  final DateTime? lastSeen;
  final DateTime createdAt;

  const DeviceModel({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    this.appVersion,
    required this.online,
    this.lastSeen,
    required this.createdAt,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      platform: json['platform'] as String,
      appVersion: json['app_version'] as String?,
      online: json['online'] as bool,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform,
        'app_version': appVersion,
        'online': online,
        'last_seen': lastSeen?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  DeviceModel copyWith({
    String? id,
    String? deviceId,
    String? deviceName,
    String? platform,
    String? appVersion,
    bool? online,
    DateTime? lastSeen,
    DateTime? createdAt,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'DeviceModel(deviceId: $deviceId, name: $deviceName, online: $online)';
}
