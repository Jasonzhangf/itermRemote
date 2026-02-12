import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/services/connection_service.dart';

void main() {
  testWidgets('Local loopback connection test', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final service = ConnectionService.instance;
      
      // Connect to local daemon
      print('[TEST] Connecting to 10.0.2.2:8766 (emulator localhost)');
      await service.connect(
        hostId: 'localhost',
        hostIp: '10.0.2.2',
        port: 8766,
      );
      
      expect(service.isConnected, true, reason: 'Should connect to daemon');
      print('[TEST] Connected successfully');
      
      // Wait for remote stream
      await Future.delayed(const Duration(seconds: 3));
      
      final hasStream = service.currentStream != null;
      print('[TEST] Has remote stream: $hasStream');
      
      // Disconnect
      await service.disconnect();
      expect(service.isConnected, false);
      print('[TEST] Disconnected');
    });
  });
}
