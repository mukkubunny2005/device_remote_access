import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remote_access/main.dart';
import 'package:remote_access/screens/splash/splash_screen.dart';

void main() {
  testWidgets('App launches and renders SplashScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: RemoteAccessApp(),
      ),
    );

    // Verify SplashScreen is rendered
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Remote Access'), findsOneWidget);
  });
}
