import 'package:flutter_test/flutter_test.dart';
import 'package:remote_access/models/pairing_model.dart';

void main() {
  group('PairingModel JSON serialization & helper tests', () {
    test('fromJson correctly parses pending pairing payload', () {
      final json = {
        'id': 'pair-uuid-123',
        'requester_device_id': '11112222',
        'target_device_id': '33334444',
        'status': 'pending',
        'created_at': '2026-08-20T12:00:00.000Z',
        'accepted_at': null,
        'revoked_at': null,
      };

      final pairing = PairingModel.fromJson(json);

      expect(pairing.id, equals('pair-uuid-123'));
      expect(pairing.requesterDeviceId, equals('11112222'));
      expect(pairing.targetDeviceId, equals('33334444'));
      expect(pairing.status, equals('pending'));
      expect(pairing.isPending, isTrue);
      expect(pairing.isAccepted, isFalse);
      expect(pairing.isRejected, isFalse);
      expect(pairing.isRevoked, isFalse);
      expect(pairing.acceptedAt, isNull);
      expect(pairing.revokedAt, isNull);
    });

    test('fromJson correctly parses accepted pairing with timestamp', () {
      final json = {
        'id': 'pair-uuid-456',
        'requester_device_id': '11112222',
        'target_device_id': '33334444',
        'status': 'accepted',
        'created_at': '2026-08-20T12:00:00.000Z',
        'accepted_at': '2026-08-20T12:05:00.000Z',
        'revoked_at': null,
      };

      final pairing = PairingModel.fromJson(json);

      expect(pairing.isAccepted, isTrue);
      expect(pairing.acceptedAt, isNotNull);
      expect(pairing.acceptedAt?.minute, equals(5));
    });

    test('peerDeviceId returns correct opposite device ID', () {
      final pairing = PairingModel(
        id: 'pair-uuid-789',
        requesterDeviceId: '11112222',
        targetDeviceId: '33334444',
        status: 'accepted',
        createdAt: DateTime.now(),
      );

      // From perspective of device A (requester)
      expect(pairing.peerDeviceId('11112222'), equals('33334444'));

      // From perspective of device B (target)
      expect(pairing.peerDeviceId('33334444'), equals('11112222'));
    });
  });
}
