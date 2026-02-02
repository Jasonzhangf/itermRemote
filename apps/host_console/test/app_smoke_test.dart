import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:host_console/main.dart';

void main() {
  testWidgets('HostConsoleApp builds', (tester) async {
    await tester.pumpWidget(const HostConsoleApp());
    expect(find.text('iTermRemote Host Console'), findsOneWidget);
  });

  testWidgets('Settings page shows Network Priority editor', (tester) async {
    await tester.pumpWidget(const HostConsoleApp());
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Network Priority'), findsOneWidget);
    expect(find.text('Save Priority Order'), findsOneWidget);
    expect(find.text('TURN Server'), findsOneWidget);
  });

  testWidgets('Advanced page builds', (tester) async {
    await tester.pumpWidget(const HostConsoleApp());
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Advanced Settings'), findsOneWidget);
    expect(find.text('Recovery Policy'), findsOneWidget);
    expect(find.text('Simulation Mode'), findsOneWidget);
  });

  testWidgets('Simulation page builds', (tester) async {
    await tester.pumpWidget(const HostConsoleApp());
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('Connection Simulation'), findsOneWidget);
    expect(find.text('Orchestrator Event Stream'), findsOneWidget);
  });

  testWidgets('Home page shows IPv6 Address Book section', (tester) async {
    await tester.pumpWidget(const HostConsoleApp());
    expect(find.text('IPv6 Address Book'), findsOneWidget);
  });
}
