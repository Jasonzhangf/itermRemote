import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_client/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ITerm2RemoteApp());
    
    // Just verify app launches
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
