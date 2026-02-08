import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_client/pages/streaming_page.dart';

void main() {
  testWidgets('StreamingPage builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreamingPage()));
    
    // Just verify page builds
    expect(find.byType(StreamingPage), findsOneWidget);
  });
}
