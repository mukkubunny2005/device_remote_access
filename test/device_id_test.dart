import 'package:flutter_test/flutter_test.dart';
import 'package:remote_access/services/device_service.dart';

void main() {
  group('DeviceService — ID generation', () {
    final service = DeviceService();

    test('generated ID is exactly 8 characters', () {
      // Access the private generator via repeated calls
      // (we call getOrCreateDeviceId indirectly via a fresh service on each test)
      // Here we test the format contract directly.
      final id = service.testGenerateDeviceId();
      expect(id.length, equals(8));
    });

    test('generated ID contains only digits', () {
      for (int i = 0; i < 20; i++) {
        final id = service.testGenerateDeviceId();
        expect(RegExp(r'^\d{8}$').hasMatch(id), isTrue,
            reason: 'ID "$id" is not 8 digits');
      }
    });

    test('generated IDs are different across calls (probabilistic)', () {
      // With 10^8 possible IDs, two in a row matching is astronomically unlikely
      final ids = List.generate(10, (_) => service.testGenerateDeviceId());
      final unique = ids.toSet();
      expect(unique.length, greaterThan(1));
    });
  });
}
