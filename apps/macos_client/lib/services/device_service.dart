import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class DeviceService {
  DeviceService._();
  static final instance = DeviceService._();

  Future<void> reportDeviceStatus({required bool isOnline}) async {
    final token = AuthService.instance.accessToken;
    if (token == null) {
      return;
    }

    final info = await _getNetworkInfo();
    final deviceId = _getDeviceId();

    final body = jsonEncode({
      'device_id': deviceId,
      'device_name': Platform.localHostname,
      'device_type': Platform.operatingSystem,
      'ipv4_lan': info['ipv4_lan'],
      'ipv4_tailscale': info['ipv4_tailscale'],
      'ipv6_public': info['ipv6_public'],
      'is_online': isOnline,
    });

    final resp = await http.post(
      Uri.parse('http://code.codewhisper.cc:8080/api/v1/device/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode == 401) {
      await AuthService.instance.logout();
      return;
    }

    if (resp.statusCode != 200) {
      // do not throw to avoid crash from timer
      print('[DeviceService] Status report failed: ${resp.statusCode}');
    }
  }

  Future<List<DeviceInfo>> getDevices() async {
    final token = AuthService.instance.accessToken;
    if (token == null) {
      return [];
    }

    final resp = await http.get(
      Uri.parse('http://code.codewhisper.cc:8080/api/v1/devices'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (resp.statusCode == 401) {
      await AuthService.instance.logout();
      return [];
    }

    if (resp.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(resp.body);
    final list = data['devices'] as List? ?? [];
    return list.map((e) => DeviceInfo.fromJson(e)).toList();
  }

  String _getDeviceId() {
    return Platform.localHostname;
  }

  Future<Map<String, List<String>>> _getNetworkInfo() async {
    final interfaces = await NetworkInterface.list(includeLinkLocal: false, includeLoopback: false);

    final ipv4Lan = <String>[];
    final ipv4Ts = <String>[];
    final ipv6Public = <String>[];

    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        final address = addr.address;
        if (addr.type == InternetAddressType.IPv4) {
          if (interface.name.contains('tailscale') ||
              interface.name.contains('ts0') ||
              address.startsWith('100.')) {
            ipv4Ts.add(address);
          } else {
            ipv4Lan.add(address);
          }
        } else if (addr.type == InternetAddressType.IPv6) {
          final normalized = _normalizeIpv6(address);
          if (_isPublicIpv6(normalized)) {
            ipv6Public.add(normalized);
          }
        }
      }
    }

    return {
      'ipv4_lan': ipv4Lan,
      'ipv4_tailscale': ipv4Ts,
      'ipv6_public': ipv6Public,
    };
  }

  String _normalizeIpv6(String address) {
    final idx = address.indexOf('%');
    if (idx >= 0) {
      return address.substring(0, idx).toLowerCase();
    }
    return address.toLowerCase();
  }

  bool _isPublicIpv6(String ip) {
    if (ip.isEmpty || ip == '::' || ip == '::1') return false;
    if (ip.startsWith('fe80:')) return false; // link-local
    if (ip.startsWith('ff')) return false; // multicast
    if (ip.startsWith('fc') || ip.startsWith('fd')) return false; // ULA/private
    if (ip.startsWith('fec0:')) return false; // deprecated site-local
    return true;
  }
}

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String deviceType;
  final List<String> ipv4Lan;
  final List<String> ipv4Tailscale;
  final List<String> ipv6Public;
  final bool isOnline;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.ipv4Lan,
    required this.ipv4Tailscale,
    required this.ipv6Public,
    required this.isOnline,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] ?? '',
      deviceName: json['device_name'] ?? '',
      deviceType: json['device_type'] ?? '',
      ipv4Lan: List<String>.from(json['ipv4_lan'] ?? []),
      ipv4Tailscale: List<String>.from(json['ipv4_tailscale'] ?? []),
      ipv6Public: List<String>.from(json['ipv6_public'] ?? []),
      isOnline: json['is_online'] ?? false,
    );
  }
}
