import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 定期上报本机公网 IP（IPv4/IPv6）到远程服务器
class IpReporter {
  IpReporter({
    required this.serverHost,
    required this.serverPort,
    required this.token,
    this.interval = const Duration(minutes: 1),
  });

  final String serverHost;
  final int serverPort;
  final String token;
  final Duration interval;

  WebSocket? _socket;
  Timer? _reportTimer;
  String? _lastIpv4;
  String? _lastIpv6;

  Future<void> start() async {
    await _connect();
    _reportTimer = Timer.periodic(interval, (_) => _report());
    // 立即上报一次
    await _report();
  }

  Future<void> stop() async {
    _reportTimer?.cancel();
    _reportTimer = null;
    await _socket?.close();
    _socket = null;
  }

  Future<void> _connect() async {
    if (_socket != null) return;
    
    final wsUrl = 'ws://$serverHost:$serverPort/ws/connect?token=$token';
    try {
      _socket = await WebSocket.connect(wsUrl);
      print('[IpReporter] Connected to $wsUrl');
      
      _socket!.listen(
        (data) => _handleMessage(data),
        onError: (e) => _handleError(e),
        onDone: () => _handleDone(),
      );
    } catch (e) {
      print('[IpReporter] Connection failed: $e');
      // 5 秒后重连
      await Future.delayed(Duration(seconds: 5));
      await _connect();
    }
  }

  Future<void> _report() async {
    // 获取公网 IP
    final ipv4 = await _fetchPublicIp(useIpv6: false);
    final ipv6 = await _fetchPublicIp(useIpv6: true);
    
    if (ipv4 != null && ipv4 != _lastIpv4) {
      _lastIpv4 = ipv4;
      print('[IpReporter] Public IPv4: $ipv4');
    }
    if (ipv6 != null && ipv6 != _lastIpv6) {
      _lastIpv6 = ipv6;
      print('[IpReporter] Public IPv6: $ipv6');
    }
    
    // 发送到服务器
    if (_socket != null && (ipv4 != null || ipv6 != null)) {
      final msg = jsonEncode({
        'type': 'host_presence',
        'ipv4': ipv4,
        'ipv6': ipv6,
        'port': 8766,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      _socket!.add(msg);
      print('[IpReporter] Reported presence');
    }
  }

  Future<String?> _fetchPublicIp({required bool useIpv6}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = Duration(seconds: 5);
      
      final url = useIpv6 
          ? Uri.parse('https://[2606:4700:4700::1111]/cdn-cgi/trace')
          : Uri.parse('https://1.1.1.1/cdn-cgi/trace');
      
      final request = await client.getUrl(url);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      
      // 解析 Cloudflare trace 响应
      for (final line in body.split('\n')) {
        if (line.startsWith('ip=')) {
          return line.substring(3).trim();
        }
      }
    } catch (e) {
      // 降级到其他服务
      try {
        final socket = await Socket.connect(
//          useIpv6 ? 'ifconfig.co' : 'ifconfig.co',
//          80,
//          timeout: Duration(seconds: 5),
//        );
//        socket.write('GET / HTTP/1.1\r\nHost: ifconfig.co\r\n\r\n');
//        await socket.flush();
//        final response = await socket.transform(utf8.decoder).join();
//        socket.destroy();
//        
//        // 简单提取 IP
//        final ipRegex = useIpv6 
//            ? RegExp(r'([0-9a-fA-F:]{2,39})')
//            : RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})');
//        final match = ipRegex.firstMatch(response);
//        return match?.group(1);
      } catch (_) {}
    }
    return null;
  }

  void _handleMessage(dynamic data) {
    // 可以处理服务器响应
  }

  void _handleError(Object error) {
    print('[IpReporter] Error: $error');
    _socket = null;
    Future.delayed(Duration(seconds: 5), () => _connect());
  }

  void _handleDone() {
    print('[IpReporter] Disconnected');
    _socket = null;
    Future.delayed(Duration(seconds: 5), () => _connect());
  }
}
