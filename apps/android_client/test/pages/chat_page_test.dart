import 'package:android_client/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ChatPage can send a composed message and append to history',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChatPage(),
      ),
    );

    expect(find.text('No messages yet'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello\nworld');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(find.text('No messages yet'), findsNothing);
    expect(find.text('hello\nworld'), findsOneWidget);
  });
}

