import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_client/pages/chat_page.dart';

void main() {
  testWidgets('ChatPage builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ChatPage()));
    
    // Just verify page builds
    expect(find.byType(ChatPage), findsOneWidget);
  });
}
