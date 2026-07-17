import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_fluttter_app/main.dart';

void main() {
  testWidgets('SEDS login page smoke test', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const SEDSApp());

    // Verify the login page loads with the Sign In button.
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Kumaraguru SEDS'), findsOneWidget);
  });
}
