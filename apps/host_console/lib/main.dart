// ignore_for_file: directives_ordering, directives_after_declarations, duplicate_import, undefined_identifier
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ui/theme.dart';
import 'logic/app_state.dart';
import 'ui/pages/main_page.dart';
import 'services/auth_service.dart';
import 'services/daemon_manager.dart';
import 'pages/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final daemonHealthy = await DaemonManager().ensureHealthy();
  if (!daemonHealthy) {
    print('[Main] CRITICAL: Daemon failed to become healthy. Starting in degraded mode.');
  }
  await AuthService.instance.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const HostConsoleApp(),
    ),
  );
}

class HostConsoleApp extends StatefulWidget {
  const HostConsoleApp({super.key});

  @override
  State<HostConsoleApp> createState() => _HostConsoleAppState();
}

class _HostConsoleAppState extends State<HostConsoleApp> {
  bool _showLogin = false;
  String? _expiryMessage;

  @override
  void initState() {
    super.initState();
    
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
        setState(() {
          _showLogin = true;
          _expiryMessage = '登录已过期，请重新登录';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('登录已过期，请重新登录'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
    
    // 初始状态检查
    _showLogin = !AuthService.instance.isAuthenticated;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iTermRemote Console',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _showLogin
          ? LoginPage(
              onLoginSuccess: () {
                setState(() {
                  _showLogin = false;
                  _expiryMessage = null;
                });
              },
            )
          : const MainPage(),
    );
  }
}
