import 'package:android_client/pages/streaming_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StreamingPage toggles between video and chat mode',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StreamingPage(),
      ),
    );

    expect(find.text('Streaming'), findsOneWidget);
    expect(find.textContaining('Video stream surface'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chat_bubble));
    await tester.pump();

    expect(find.text('Chat Mode'), findsOneWidget);
    expect(find.text('Open Chat'), findsOneWidget);
  });
}

