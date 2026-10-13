// =============================================================================
// test/widget_test.dart
//
// A basic smoke test — just checks that the app starts without crashing
// and that the HomeScreen shows the expected buttons.
//
// WHAT IS A TEST?
//   A test is code that checks your code works correctly.
//   Flutter's WidgetTester pretends to be a phone and "runs" the app
//   without needing a real device. Then we use `expect` to assert things
//   we know should be true.
//
// HOW TO RUN TESTS:
//   flutter test
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:ridesync/main.dart';

void main() {
  testWidgets('HomeScreen renders without crashing', (tester) async {
    // Start the full app — same as pressing Run on a real device.
    await tester.pumpWidget(const RideSyncApp());

    // Wait for any async startup work to finish.
    await tester.pumpAndSettle();

    // The home screen should show the app name and its three main buttons.
    expect(find.text('RideSync'),      findsOneWidget);
    expect(find.text('Host a ride'),   findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Sign up or log in'), findsOneWidget);
  });
}
