import 'package:android_client/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ITerm2RemoteApp());

    expect(find.text('Connect to Host'), findsOneWidget);
    expect(find.text('Add Host'), findsOneWidget);
  });
}
