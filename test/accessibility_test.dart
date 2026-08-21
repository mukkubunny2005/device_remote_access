import 'package:flutter_test/flutter_test.dart';
import 'package:remote_access/providers/accessibility_provider.dart';

void main() {
  group('AccessibilityState', () {
    test('initial state defaults to disabled and disarmed', () {
      const state = AccessibilityState();
      expect(state.isEnabled, isFalse);
      expect(state.isArmed, isFalse);
    });

    test('copyWith correctly updates isEnabled', () {
      const state = AccessibilityState();
      final updated = state.copyWith(isEnabled: true);
      expect(updated.isEnabled, isTrue);
      expect(updated.isArmed, isFalse);
    });

    test('copyWith correctly updates isArmed', () {
      const state = AccessibilityState(isEnabled: true);
      final updated = state.copyWith(isArmed: true);
      expect(updated.isEnabled, isTrue);
      expect(updated.isArmed, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const state = AccessibilityState(isEnabled: true, isArmed: true);
      final updated = state.copyWith(isArmed: false);
      expect(updated.isEnabled, isTrue);
      expect(updated.isArmed, isFalse);
    });
  });
}
