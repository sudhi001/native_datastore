import 'package:flutter_test/flutter_test.dart';

import 'package:native_datastore_example/main.dart';

void main() {
  testWidgets('Verify app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Native DataStore Demo'), findsOneWidget);
  });
}
