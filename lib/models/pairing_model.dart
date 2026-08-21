/// Pairing model mirroring the backend Pairing schema.
class PairingModel {
  final String id;
  final String requesterDeviceId;
  final String targetDeviceId;
  final String status; // pending | accepted | rejected | revoked
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  const PairingModel({
    required this.id,
    required this.requesterDeviceId,
    required this.targetDeviceId,
    required this.status,
    required this.createdAt,
    this.acceptedAt,
    this.revokedAt,
  });

  factory PairingModel.fromJson(Map<String, dynamic> json) {
    return PairingModel(
      id: json['id'] as String,
      requesterDeviceId: json['requester_device_id'] as String,
      targetDeviceId: json['target_device_id'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      revokedAt: json['revoked_at'] != null
          ? DateTime.parse(json['revoked_at'] as String)
          : null,
    );
  }

  bool get isPending  => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isRevoked  => status == 'revoked';

  /// The other device ID from the perspective of [myDeviceId].
  String peerDeviceId(String myDeviceId) =>
      myDeviceId == requesterDeviceId ? targetDeviceId : requesterDeviceId;

  @override
  String toString() =>
      'PairingModel($requesterDeviceId→$targetDeviceId status=$status)';
}
