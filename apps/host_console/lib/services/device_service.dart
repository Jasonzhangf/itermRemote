import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class DeviceService {
  DeviceService._();
  static final instance = DeviceService._();

  Future<void> reportDeviceStatus({required bool isOnline}) async {
    final token = AuthService.instance.accessToken;
    if (token == null) return;

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

    await http.post(
      Uri.parse('http://code.codewhisper.cc:8080/api/v1/device/status'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );
  }

  String _getDeviceId() {
    return Platform.localHostname;
  }

  Future<Map<String, List<String>>> _getNetworkInfo() async {
    final interfaces = await NetworkInterface.list(includeLinkLocal: false, includeLoopback: false);

    final ipv4Lan = <String>[];
    final ipv4Ts = <String>[];
    final ipv6 = <String>[];

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
          ipv6.add(address);
        }
      }
    }

    return {
      'ipv4_lan': ipv4Lan,
      'ipv4_tailscale': ipv4Ts,
      'ipv6_public': ipv6,
    };
  }
}
