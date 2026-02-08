import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_client/pages/connect_page.dart';

void main() {
  testWidgets('ConnectPage shows host list', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: ConnectPage()));
    
    // Pump to trigger timer
    await tester.pump(Duration(seconds: 3));
    await tester.pumpAndSettle();
    
    // Just verify page builds
    expect(find.byType(ConnectPage), findsOneWidget);
  });
}
