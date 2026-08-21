import 'package:flutter_test/flutter_test.dart';
import 'package:remote_access/models/access_session_model.dart';

void main() {
  group('AccessSessionModel JSON serialization & helper tests', () {
    test('fromJson correctly parses pending access request', () {
      final json = {
        'id': 'session-uuid-123',
        'requester_device_id': '11112222',
        'target_device_id': '33334444',
        'status': 'pending',
        'view_only': false,
        'can_control': true,
        'session_token': null,
        'created_at': '2026-08-20T12:00:00.000Z',
        'expires_at': '2026-08-20T12:01:00.000Z',
        'accepted_at': null,
        'ended_at': null,
      };

      final session = AccessSessionModel.fromJson(json);

      expect(session.id, equals('session-uuid-123'));
      expect(session.requesterDeviceId, equals('11112222'));
      expect(session.targetDeviceId, equals('33334444'));
      expect(session.status, equals('pending'));
      expect(session.isPending, isTrue);
      expect(session.isActive, isFalse);
      expect(session.canControl, isTrue);
      expect(session.viewOnly, isFalse);
      expect(session.sessionToken, isNull);
    });

    test('fromJson correctly parses active session with token', () {
      final json = {
        'id': 'session-uuid-456',
        'requester_device_id': '11112222',
        'target_device_id': '33334444',
        'status': 'active',
        'view_only': true,
        'can_control': false,
        'session_token': 'secret-token-abcdef123456',
        'created_at': '2026-08-20T12:00:00.000Z',
        'expires_at': '2026-08-20T12:01:00.000Z',
        'accepted_at': '2026-08-20T12:00:15.000Z',
        'ended_at': null,
      };

      final session = AccessSessionModel.fromJson(json);

      expect(session.isActive, isTrue);
      expect(session.isPending, isFalse);
      expect(session.sessionToken, equals('secret-token-abcdef123456'));
      expect(session.viewOnly, isTrue);
      expect(session.canControl, isFalse);
      expect(session.acceptedAt, isNotNull);
    });

    test('peerDeviceId and isController helpers function correctly', () {
      final session = AccessSessionModel(
        id: 'session-uuid-789',
        requesterDeviceId: '11112222',
        targetDeviceId: '33334444',
        status: 'active',
        viewOnly: false,
        canControl: true,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      );

      expect(session.peerDeviceId('11112222'), equals('33334444'));
      expect(session.peerDeviceId('33334444'), equals('11112222'));
      expect(session.isController('11112222'), isTrue);
      expect(session.isController('33334444'), isFalse);
    });
  });
}
