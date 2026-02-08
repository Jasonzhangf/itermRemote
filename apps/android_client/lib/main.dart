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

/// iTerm2 Remote Android client entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.instance.init();
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

    _showLogin = !AuthService.instance.isAuthenticated;
    if (!_showLogin) {
      _startStatusReporting();
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
