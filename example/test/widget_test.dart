import 'package:flutter_test/flutter_test.dart';

import 'package:native_datastore_example/main.dart';

void main() {
  testWidgets('Verify app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // The app opens on the "Regular" tab: its AppBar title and the two
    // bottom-navigation labels should be visible.
    expect(find.text('Regular Storage'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Secure'), findsOneWidget);
  });
}
