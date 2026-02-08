import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_client/main.dart';

void main() {
  testWidgets('App builds and shows login page', (WidgetTester tester) async {
    await tester.pumpWidget(const ITerm2RemoteApp());
    
    // Wait for auth service to init
    await tester.pumpAndSettle();
    
    // Should show login page
    expect(find.text('ItermRemote'), findsOneWidget);
    expect(find.text('登录到您的账号'), findsOneWidget);
  });
}
