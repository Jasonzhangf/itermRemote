import "dart:async";
import "dart:convert";
import "dart:io";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";

import "remote_ws_service.dart";
import "ws_client.dart";
import "device_service.dart";
import "daemon_manager.dart";

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const String _apiBaseUrl = "http://code.codewhisper.cc:8080";
  static const String _tokenKey = "auth_token";
  static const String _refreshTokenKey = "refresh_token";
  static const String _userKey = "user_data";
  static const String _tokenExpiryKey = "token_expiry";

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _currentUser;
  DateTime? _tokenExpiry;
  Timer? _refreshTimer;
  Timer? _statusTimer;
  bool _isWsConnecting = false;
  bool _isWsConnected = false;

  final _authController = StreamController<AuthState>.broadcast();
  final _tokenExpiredController = StreamController<void>.broadcast();
  final _wsStateController = StreamController<WsConnectionState>.broadcast();

  Stream<AuthState> get authState => _authController.stream;
  Stream<void> get tokenExpired => _tokenExpiredController.stream;
  Stream<WsConnectionState> get wsState => _wsStateController.stream;
  bool get isAuthenticated => _accessToken != null && !isTokenExpired;
  bool get isTokenExpired => _tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!);
  bool get isWsConnected => _isWsConnected;
  String? get accessToken => _accessToken;
  Map<String, dynamic>? get currentUser => _currentUser;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_tokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    final userJson = prefs.getString(_userKey);
    final expiryStr = prefs.getString(_tokenExpiryKey);

    if (userJson != null) {
      _currentUser = jsonDecode(userJson);
    }
    if (expiryStr != null) {
      _tokenExpiry = DateTime.parse(expiryStr);
    }

    if (_accessToken != null) {
      if (isTokenExpired) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) {
          await logout();
          _authController.add(AuthState.unauthenticated);
          return;
        }
      }
      _authController.add(AuthState.authenticated);
      _startAutoRefresh();
      _startStatusReporting();
      _connectToDaemon();
    } else {
      _authController.add(AuthState.unauthenticated);
    }
  }

  Future<void> _connectToDaemon() async {
    if (_isWsConnecting || _isWsConnected) return;
    if (_accessToken == null) return;

    // Health check before attempting WS connection
    final daemonHealthy = await DaemonManager().ensureHealthy();
    if (!daemonHealthy) {
      print("[WS] Daemon not healthy, deferring connection");
      _isWsConnecting = false;
      Future.delayed(const Duration(seconds: 5), () => _connectToDaemon());
      return;
    }

    _isWsConnecting = true;
    _wsStateController.add(WsConnectionState.connecting);

    try {
      // Use WsClient for daemon control. Do not append token in URL.
      await WsClient(url: 'ws://127.0.0.1:8766').connect();

      _isWsConnected = true;
      _isWsConnecting = false;
      _wsStateController.add(WsConnectionState.connected);

      await _reportLocalStatus();

      await RemoteWsService.instance.connect();

    } catch (e) {
      print("[WS] Connection failed: $e");
      _isWsConnecting = false;
      _wsStateController.add(WsConnectionState.disconnected);
      Future.delayed(const Duration(seconds: 5), () => _connectToDaemon());
    }
  }

  Future<void> _reportLocalStatus() async {
    if (!_isWsConnected || _accessToken == null) return;

    final networkInfo = await _getNetworkInfo();
    print("[Status] Reporting local status: $networkInfo");
  }

  Future<Map<String, dynamic>> _getNetworkInfo() async {
    final interfaces = await NetworkInterface.list(includeLinkLocal: false, includeLoopback: false);

    final ipv4Addrs = <String>[];
    final ipv6Addrs = <String>[];

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          ipv4Addrs.add(addr.address);
        } else if (addr.type == InternetAddressType.IPv6) {
          ipv6Addrs.add(addr.address);
        }
      }
    }

    return {
      "ipv4": ipv4Addrs,
      "ipv6": ipv6Addrs,
      "timestamp": DateTime.now().toIso8601String(),
    };
  }

  Future<LoginResult> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$_apiBaseUrl/api/v1/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data["access_token"];
        _refreshToken = data["refresh_token"];

        final expiresIn = data["expires_in"] ?? 1800;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

        await _fetchProfile();
        await _saveCredentials();

        _startAutoRefresh();
        _startStatusReporting();
        _authController.add(AuthState.authenticated);

        _connectToDaemon();

        return LoginResult.success();
      } else {
        final error = jsonDecode(response.body);
        return LoginResult.failure(error["error"] ?? "登录失败");
      }
    } catch (e) {
      return LoginResult.failure("网络错误: ${e.toString()}");
    }
  }

  Future<RegisterResult> register(String username, String email, String password, String nickname) async {
    try {
      final response = await http.post(
        Uri.parse("$_apiBaseUrl/api/v1/register"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "email": email,
          "password": password,
          "nickname": nickname,
        }),
      );

      if (response.statusCode == 201) {
        return RegisterResult.success();
      } else {
        final error = jsonDecode(response.body);
        return RegisterResult.failure(error["error"] ?? "注册失败");
      }
    } catch (e) {
      return RegisterResult.failure("网络错误: ${e.toString()}");
    }
  }

  Future<void> _fetchProfile() async {
    if (_accessToken == null) return;

    try {
      final response = await http.get(
        Uri.parse("$_apiBaseUrl/api/v1/user/profile"),
        headers: {"Authorization": "Bearer $_accessToken"},
      );

      if (response.statusCode == 200) {
        _currentUser = jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        await _handleTokenExpired();
      }
    } catch (e) {
      print("[Auth] Failed to fetch profile: $e");
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await prefs.setString(_tokenKey, _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
    }
    if (_currentUser != null) {
      await prefs.setString(_userKey, jsonEncode(_currentUser));
    }
    if (_tokenExpiry != null) {
      await prefs.setString(_tokenExpiryKey, _tokenExpiry!.toIso8601String());
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (_accessToken != null) {
        refreshAccessToken();
      }
    });
  }

  void _startStatusReporting() {
    _statusTimer?.cancel();
    DeviceService.instance.reportDeviceStatus(isOnline: true);
    _statusTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => DeviceService.instance.reportDeviceStatus(isOnline: true),
    );
  }

  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse("$_apiBaseUrl/api/v1/token/refresh"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"refresh_token": _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data["access_token"];

        final expiresIn = data["expires_in"] ?? 1800;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

        await _saveCredentials();
        print("[Auth] Token refreshed successfully");
        return true;
      } else if (response.statusCode == 401) {
        await _handleTokenExpired();
        return false;
      }
    } catch (e) {
      print("[Auth] Token refresh failed: $e");
    }
    return false;
  }

  Future<void> _handleTokenExpired() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _tokenExpiredController.add(null);
    await logout();
  }

  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;
    _tokenExpiry = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
    _isWsConnected = false;
    _isWsConnecting = false;

    RemoteWsService.instance.disconnect();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_tokenExpiryKey);

    _authController.add(AuthState.unauthenticated);
    _wsStateController.add(WsConnectionState.disconnected);
  }

  void dispose() {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    _authController.close();
    _tokenExpiredController.close();
    _wsStateController.close();
  }
}

enum AuthState { authenticated, unauthenticated }
enum WsConnectionState { connecting, connected, disconnected }

class LoginResult {
  final bool success;
  final String? error;

  LoginResult._({required this.success, this.error});

  factory LoginResult.success() => LoginResult._(success: true);
  factory LoginResult.failure(String error) => LoginResult._(success: false, error: error);
}

class RegisterResult {
  final bool success;
  final String? error;

  RegisterResult._({required this.success, this.error});

  factory RegisterResult.success() => RegisterResult._(success: true);
  factory RegisterResult.failure(String error) => RegisterResult._(success: false, error: error);
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => "AuthException: $message";
}
