import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_ws_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();
  
  static const String _apiBaseUrl = 'http://code.codewhisper.cc:8080';
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'user_data';
  static const String _tokenExpiryKey = 'token_expiry';
  
  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _currentUser;
  DateTime? _tokenExpiry;
  Timer? _refreshTimer;
  
  final _authController = StreamController<AuthState>.broadcast();
  final _tokenExpiredController = StreamController<void>.broadcast();
  
  Stream<AuthState> get authState => _authController.stream;
  Stream<void> get tokenExpired => _tokenExpiredController.stream;
  bool get isAuthenticated => _accessToken != null && !isTokenExpired;
  bool get isTokenExpired => _tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!);
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
      _connectToRemoteWs();
    } else {
      _authController.add(AuthState.unauthenticated);
    }
  }
  
  void _connectToRemoteWs() {
    RemoteWsService.instance.connect();
  }
  
  Future<LoginResult> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        
        final expiresIn = data['expires_in'] ?? 1800;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        
        await _fetchProfile();
        await _saveCredentials();
        
        _startAutoRefresh();
        _authController.add(AuthState.authenticated);
        _connectToRemoteWs();
        return LoginResult.success();
      } else {
        final error = jsonDecode(response.body);
        return LoginResult.failure(error['error'] ?? '登录失败');
      }
    } catch (e) {
      return LoginResult.failure('网络错误: ${e.toString()}');
    }
  }
  
  Future<RegisterResult> register(String username, String email, String password, String nickname) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'nickname': nickname,
        }),
      );
      
      if (response.statusCode == 201) {
        return RegisterResult.success();
      } else {
        final error = jsonDecode(response.body);
        return RegisterResult.failure(error['error'] ?? '注册失败');
      }
    } catch (e) {
      return RegisterResult.failure('网络错误: ${e.toString()}');
    }
  }
  
  Future<void> _fetchProfile() async {
    if (_accessToken == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/v1/user/profile'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      
      if (response.statusCode == 200) {
        _currentUser = jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        await _handleTokenExpired();
      }
    } catch (e) {
      print('[Auth] Failed to fetch profile: $e');
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
  
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;
    
    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/token/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        
        final expiresIn = data['expires_in'] ?? 1800;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        
        await _saveCredentials();
        print('[Auth] Token refreshed successfully');
        return true;
      } else if (response.statusCode == 401) {
        await _handleTokenExpired();
        return false;
      }
    } catch (e) {
      print('[Auth] Token refresh failed: $e');
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
    
    RemoteWsService.instance.disconnect();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_tokenExpiryKey);
    
    _authController.add(AuthState.unauthenticated);
  }
  
  Future<http.Response> authenticatedRequest(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    if (_accessToken == null) {
      throw AuthException('Not authenticated');
    }
    
    if (_tokenExpiry != null && 
        DateTime.now().add(const Duration(minutes: 5)).isAfter(_tokenExpiry!)) {
      final refreshed = await refreshAccessToken();
      if (!refreshed) {
        throw AuthException('Token expired');
      }
    }
    
    final requestHeaders = {
      'Authorization': 'Bearer $_accessToken',
      ...?headers,
    };
    
    late http.Response response;
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(
          Uri.parse('$_apiBaseUrl$path'),
          headers: requestHeaders,
        );
        break;
      case 'POST':
        response = await http.post(
          Uri.parse('$_apiBaseUrl$path'),
          headers: requestHeaders,
          body: body,
        );
        break;
      default:
        throw UnsupportedError('HTTP method $method not supported');
    }
    
    if (response.statusCode == 401) {
      await _handleTokenExpired();
      throw AuthException('Token expired');
    }
    
    return response;
  }
  
  void dispose() {
    _refreshTimer?.cancel();
    _authController.close();
    _tokenExpiredController.close();
  }
}

enum AuthState { authenticated, unauthenticated }

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
  String toString() => 'AuthException: $message';
}
