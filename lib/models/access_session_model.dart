/// Remote access session model.
class AccessSessionModel {
  final String id;
  final String requesterDeviceId;
  final String targetDeviceId;
  final String status; // pending | active | rejected | expired | ended
  final bool viewOnly;
  final bool canControl;
  final String? sessionToken;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;

  const AccessSessionModel({
    required this.id,
    required this.requesterDeviceId,
    required this.targetDeviceId,
    required this.status,
    required this.viewOnly,
    required this.canControl,
    this.sessionToken,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedAt,
    this.endedAt,
  });

  factory AccessSessionModel.fromJson(Map<String, dynamic> json) {
    return AccessSessionModel(
      id: json['id'] as String,
      requesterDeviceId: json['requester_device_id'] as String,
      targetDeviceId: json['target_device_id'] as String,
      status: json['status'] as String,
      viewOnly: json['view_only'] as bool? ?? false,
      canControl: json['can_control'] as bool? ?? false,
      sessionToken: json['session_token'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';
  bool get isEnded => status == 'ended';

  String peerDeviceId(String myDeviceId) =>
      myDeviceId == requesterDeviceId ? targetDeviceId : requesterDeviceId;

  bool isController(String myDeviceId) => requesterDeviceId == myDeviceId;
}
