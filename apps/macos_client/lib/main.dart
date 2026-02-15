import "dart:io";
import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "theme.dart";
import "widgets/desktop_simulator.dart";
import "pages/main_shell.dart";
import "pages/streaming_page.dart";
import "pages/login_page.dart";
import "services/auth_service.dart";
import "services/device_service.dart";
import "services/connection_service.dart";
import "services/automation_ws_service.dart";

/// iTerm2 Remote Android client entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.init();
  
  // Start automation WebSocket for testing
  AutomationWsService.instance.getStateCallback = () => {
    'status': 'running',
    'authenticated': true, // Local testing: always authenticated
    'isConnected': ConnectionService.instance.isConnected,
    'connectedHostId': ConnectionService.instance.connectedHostId,
    'hasStream': ConnectionService.instance.currentStream != null,
    'frameCount': ConnectionService.instance.frameCount,
    'fps': ConnectionService.instance.currentFps,
  };
  AutomationWsService.instance.executeActionCallback = (action, params) async {
    print('[Automation] Execute: $action with $params');
    try {
      switch (action) {
        case 'connectLoopback':
          await ConnectionService.instance.connect(
            hostId: 'localhost',
            hostIp: '127.0.0.1',
            port: 8766,
          );
          // If iTerm2 window capture path fails, retry with plain screen capture
          if (!ConnectionService.instance.isConnected) {
            try {
              ConnectionService.instance.sendCmd('webrtc', 'startLoopback', {
                'sourceType': 'screen',
                'fps': 30,
                'width': 1920,
                'height': 1080,
                'bitrateKbps': 2000,
              });
            } catch (_) {}
          }
return {'success': true, 'action': action, 'connected': ConnectionService.instance.isConnected};
        case 'connectViaRelay':
          final hostDeviceId = params['hostDeviceId'] ?? 'host-loopback-test';
          print('[Automation] Connecting via relay: $hostDeviceId');
          await ConnectionService.instance.connectViaRelay(hostDeviceId: hostDeviceId);
          return {
            'success': true,
            'action': action,
            'hostDeviceId': hostDeviceId,
            'connected': ConnectionService.instance.isConnected,
          };
        case 'connectIPv6':
          final hostId = params['hostId'] ?? 'unknown';
          final ipv6 = params['ipv6'] ?? '';
          final port = params['port'] ?? 8766;
          print('[Automation] Connecting IPv6: $ipv6:$port');
          await ConnectionService.instance.connect(
            hostId: hostId,
            hostIp: ipv6,
            port: port,
          );
          return {'success': true, 'action': action, 'connected': ConnectionService.instance.isConnected};
        case 'disconnect':
          await ConnectionService.instance.disconnect();
          return {'success': true, 'action': action};
        default:
          return {'success': false, 'error': 'Unknown action: $action'};
      }
    } catch (e, stack) {
      print('[Automation] Execute error: $e');
      print('[Automation] Stack: $stack');
      return {'success': false, 'error': e.toString()};
    }
  };
  AutomationWsService.instance.start(port: 9999);
  runApp(const ITerm2RemoteApp());
}

class ITerm2RemoteApp extends StatefulWidget {
  const ITerm2RemoteApp({super.key});

  @override
  State<ITerm2RemoteApp> createState() => _ITerm2RemoteAppState();
}

class _ITerm2RemoteAppState extends State<ITerm2RemoteApp> with WidgetsBindingObserver {
  bool _showLogin = false;
  Timer? _statusReportTimer;
  bool _isReporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Auto-login for macOS testing
    _tryAutoLogin();

    // 监听认证状态变化
    AuthService.instance.authState.listen((state) {
      if (mounted) {
        setState(() {
          _showLogin = state == AuthState.unauthenticated;
        });
      }
    });

    // 监听token过期事件
    AuthService.instance.tokenExpired.listen((_) {
      if (mounted) {
        setState(() => _showLogin = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("登录已过期，请重新登录"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });

    // For macOS local testing, skip login
  const skipLogin = true; // Set to false to require auth
  _showLogin = !skipLogin && !AuthService.instance.isAuthenticated;
    if (!_showLogin) {
      _startStatusReporting();
    }
  }

Future<void> _tryAutoLogin() async {
    // For macOS local testing: auto-login with test account
    const testUsername = 'testrelay';
    const testPassword = 'testpass123';
    
    print('[AutoLogin] Attempting auto-login with $testUsername');
    final result = await AuthService.instance.login(testUsername, testPassword);
    
    if (result.success) {
      print('[AutoLogin] Auto-login successful');
      if (mounted) {
        setState(() => _showLogin = false);
        _startStatusReporting();
      }
    } else {
      print('[AutoLogin] Auto-login failed: ${result.error}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // 回到前台，恢复上报
        if (!_showLogin && !_isReporting) {
          _startStatusReporting();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // 进入后台或销毁，上报离线
        if (_isReporting) {
          _pauseStatusReporting();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _startStatusReporting() {
    _isReporting = true;
    DeviceService.instance.reportDeviceStatus(isOnline: true);
    _statusReportTimer?.cancel();
    _statusReportTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => DeviceService.instance.reportDeviceStatus(isOnline: true),
    );
  }

  void _pauseStatusReporting() {
    _statusReportTimer?.cancel();
    _statusReportTimer = null;
    DeviceService.instance.reportDeviceStatus(isOnline: false);
  }

  void _stopStatusReporting() {
    _isReporting = false;
    _statusReportTimer?.cancel();
    _statusReportTimer = null;
    DeviceService.instance.reportDeviceStatus(isOnline: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStatusReporting();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopFalse = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    return MaterialApp(
      title: "iTerm2 Remote",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) {
        if (!isDesktopFalse) return child ?? const SizedBox.shrink();
        return DesktopSimulator(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _showLogin
          ? LoginPage(
              onLoginSuccess: () {
                setState(() => _showLogin = false);
                _startStatusReporting();
              },
            )
          : const MainShell(),
      routes: {
        "/streaming": (context) => const StreamingPage(),
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(builder: (context) => const MainShell());
      },
    );
  }
}
