import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:host_test_app/main.dart';

void main() {
  testWidgets('HostTestApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HostTestApp(),
      ),
    );
    // Avoid running async init in widget tests.
    await tester.pumpAndSettle();
    expect(find.text('Encoding Profile'), findsOneWidget);
  });
}
