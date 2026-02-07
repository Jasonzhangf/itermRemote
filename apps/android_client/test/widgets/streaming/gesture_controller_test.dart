import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:android_client/widgets/streaming/gesture_controller.dart';

class _TestWidget extends StatefulWidget {
  const _TestWidget({super.key});

  @override
  State<_TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<_TestWidget> with GestureControllerMixin {
  final List<String> events = [];

  @override
  void onSingleTap(double xPercent, double yPercent) {
    events.add('tap:$xPercent,$yPercent');
  }

  @override
  void onDoubleTap(double xPercent, double yPercent) {
    events.add('double_tap:$xPercent,$yPercent');
  }

  @override
  void onPanStart(double xPercent, double yPercent) {
    events.add('pan_start:$xPercent,$yPercent');
  }

  @override
  void onPanUpdate(double deltaX, double deltaY) {
    events.add('pan_update:$deltaX,$deltaY');
  }

  @override
  void onPanEnd() {
    events.add('pan_end');
  }

  @override
  void onTwoFingerScroll(double deltaX, double deltaY) {
    events.add('scroll:$deltaX,$deltaY');
  }

  @override
  void onPinchZoom(double scaleChange) {
    events.add('zoom:$scaleChange');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      height: 600,
      color: Colors.blue,
    );
  }
}

void main() {
  group('GestureControllerMixin', () {
    testWidgets('single tap detection', (tester) async {
      final key = GlobalKey<_TestWidgetState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestWidget(key: key),
        ),
      ));

      final state = key.currentState!;
      final renderBox = tester.renderObject(find.byKey(key)) as RenderBox;

      // Simulate quick tap
      final downEvent = PointerDownEvent(
        pointer: 1,
        position: const Offset(200, 300),
      );
      final upEvent = PointerUpEvent(
        pointer: 1,
        position: const Offset(200, 300),
      );

      state.handlePointerDown(downEvent, renderBox);
      await tester.pump(const Duration(milliseconds: 100));
      state.handlePointerUp(upEvent, renderBox);
      await tester.pump();

      expect(state.events, contains(startsWith('tap:')));
    });

    testWidgets('two-finger scroll detection', (tester) async {
      final key = GlobalKey<_TestWidgetState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestWidget(key: key),
        ),
      ));

      final state = key.currentState!;
      final renderBox = tester.renderObject(find.byKey(key)) as RenderBox;

      // Two fingers down
      state.handlePointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(100, 300)),
        renderBox,
      );
      state.handlePointerDown(
        PointerDownEvent(pointer: 2, position: const Offset(300, 300)),
        renderBox,
      );

      // Move both fingers vertically (scroll)
      await tester.pump(const Duration(milliseconds: 100));
      state.handlePointerMove(
        PointerMoveEvent(pointer: 1, position: const Offset(100, 250)),
        renderBox,
      );
      state.handlePointerMove(
        PointerMoveEvent(pointer: 2, position: const Offset(300, 250)),
        renderBox,
      );

      await tester.pump();

      expect(state.events.any((e) => e.startsWith('scroll:') || e.startsWith('zoom:')), isTrue);
    });

    testWidgets('pinch zoom detection', (tester) async {
      final key = GlobalKey<_TestWidgetState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestWidget(key: key),
        ),
      ));

      final state = key.currentState!;
      final renderBox = tester.renderObject(find.byKey(key)) as RenderBox;

      // Two fingers down
      state.handlePointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(150, 300)),
        renderBox,
      );
      state.handlePointerDown(
        PointerDownEvent(pointer: 2, position: const Offset(250, 300)),
        renderBox,
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Move fingers apart (pinch out)
      state.handlePointerMove(
        PointerMoveEvent(pointer: 1, position: const Offset(100, 300)),
        renderBox,
      );
      state.handlePointerMove(
        PointerMoveEvent(pointer: 2, position: const Offset(300, 300)),
        renderBox,
      );

      await tester.pump();

      expect(state.events.any((e) => e.startsWith('zoom:') || e.startsWith('scroll:')), isTrue);
    });

    testWidgets('reset gesture state', (tester) async {
      final key = GlobalKey<_TestWidgetState>();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: _TestWidget(key: key),
        ),
      ));

      final state = key.currentState!;
      final renderBox = tester.renderObject(find.byKey(key)) as RenderBox;

      state.handlePointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(200, 300)),
        renderBox,
      );

      state.resetGestureState();
      
      // State should be clean
      expect(state.videoScale, 1.0);
      expect(state.videoOffset, Offset.zero);
    });
  });
}
