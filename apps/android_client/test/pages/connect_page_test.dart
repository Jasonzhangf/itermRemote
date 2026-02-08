import 'package:android_client/pages/connect_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ConnectPage shows host list and Add Host button',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ConnectPage(),
      ),
    );

    expect(find.text('Connect to Host'), findsOneWidget);
    expect(find.text('Add Host'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
  });
}

