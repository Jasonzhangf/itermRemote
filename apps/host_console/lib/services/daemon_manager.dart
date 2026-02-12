import 'dart:io';
import 'dart:async';
import 'dart:convert';

/// Manages the local iTermRemote daemon process
class DaemonManager {
  static final DaemonManager _instance = DaemonManager._internal();
  factory DaemonManager() => _instance;
  DaemonManager._internal();

  Process? _daemonProcess;
  bool _isRunning = false;
  bool _isHealthy = false;
  final _statusController = StreamController<bool>.broadcast();
  final _healthController = StreamController<bool>.broadcast();

  Stream<bool> get statusStream => _statusController.stream;
  Stream<bool> get healthStream => _healthController.stream;
  bool get isRunning => _isRunning;
  bool get isHealthy => _isHealthy;

  /// Check if daemon port is open (basic connectivity)
  Future<bool> checkDaemon() async {
    try {
      final socket = await Socket.connect('127.0.0.1', 8766, timeout: const Duration(milliseconds: 500));
      await socket.close();
      _isRunning = true;
      if (!_statusController.isClosed) _statusController.add(true);
      return true;
    } catch (_) {
      _isRunning = false;
      if (!_statusController.isClosed) _statusController.add(false);
      return false;
    }
  }

  /// Check daemon health (port check + optional HTTP health endpoint)
  Future<bool> checkHealth() async {
    // First check if port is open
    if (!await checkDaemon()) {
      _isHealthy = false;
      if (!_healthController.isClosed) _healthController.add(false);
      return false;
    }
    
    // Try HTTP health endpoint if available, otherwise consider port open as healthy
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 1);
      final request = await client.get('127.0.0.1', 8766, '/health');
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);
        final healthy = json['status'] == 'ok' || json['healthy'] == true;
        
        _isHealthy = healthy;
        if (!_healthController.isClosed) _healthController.add(healthy);
        client.close();
        return healthy;
      }
      client.close();
    } catch (e) {
      // HTTP endpoint not available - port open is sufficient for health
      print('[DaemonManager] HTTP health endpoint not available, using port check');
    }
    
    // Port is open, consider healthy
    _isHealthy = true;
    if (!_healthController.isClosed) _healthController.add(true);
    return true;
  }

  /// Wait for daemon to become healthy (with timeout)
  Future<bool> waitForHealthy({Duration timeout = const Duration(seconds: 30)}) async {
    final stopwatch = Stopwatch()..start();
    
    while (stopwatch.elapsed < timeout) {
      if (await checkHealth()) {
        print('[DaemonManager] Daemon is healthy');
        return true;
      }
      
      // If port not even open, try to start daemon
      if (!await checkDaemon()) {
        print('[DaemonManager] Daemon not running, attempting to start...');
        await startDaemon();
      }
      
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    print('[DaemonManager] Daemon health check timed out');
    return false;
  }

  /// Start the daemon process
  Future<bool> startDaemon() async {
    if (await checkHealth()) return true;

    try {
      print('[DaemonManager] Starting daemon via launchctl...');

      final home = Platform.environment['HOME'] ?? '/Users/fanzhang';
      final plistPath = '$home/Library/LaunchAgents/com.itermremote.host-daemon.plist';

      await Process.run('launchctl', ['load', plistPath]);

      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (await checkHealth()) {
          print('[DaemonManager] Daemon started and healthy');
          return true;
        }
      }

      print('[DaemonManager] Daemon failed to start via launchctl');
      return false;
    } catch (e) {
      print('[DaemonManager] Failed to start daemon: $e');
      return false;
    }
  }

  /// Stop the daemon
  Future<void> stopDaemon() async {
    if (_daemonProcess != null) {
      _daemonProcess!.kill();
      _daemonProcess = null;
    }
    _isRunning = false;
    _isHealthy = false;
    if (!_statusController.isClosed) _statusController.add(false);
    if (!_healthController.isClosed) _healthController.add(false);
  }

  /// Ensure daemon is running and healthy
  Future<bool> ensureHealthy() async {
    if (await checkHealth()) {
      return true;
    }
    return await waitForHealthy();
  }

  Future<String?> _findDaemonBinary() async {
    // Deprecated: daemon uses launchctl service now.
    return null;
  }

  void dispose() {
    _statusController.close();
    _healthController.close();
  }
}
