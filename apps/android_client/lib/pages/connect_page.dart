import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/device_service.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  List<DeviceInfo> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 先上报自己的 IP
      await DeviceService.instance.reportDeviceStatus(isOnline: true);

      // 获取设备列表
      final devices = await DeviceService.instance.getDevices();
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connectToDevice(DeviceInfo device) async {
    // 按顺序尝试: IPv6 公网 -> IPv4 Tailscale -> IPv4 LAN
    final targets = <String>[];
    targets.addAll(device.ipv6Public);
    targets.addAll(device.ipv4Tailscale);
    targets.addAll(device.ipv4Lan);

    for (final ip in targets) {
      try {
        await ConnectionService.instance.connect(
          hostId: device.deviceId,
          hostIp: ip,
          port: 8766,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已连接: $ip')),
          );
        }
        return;
      } catch (e) {
        // 尝试下一个
        continue;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法连接到该设备')),
      );
    }
  }

  Widget _buildDeviceCard(DeviceInfo device) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        leading: const Icon(Icons.desktop_windows),
        title: Text(device.deviceName.isEmpty ? device.deviceId : device.deviceName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (device.ipv6Public.isNotEmpty)
              Text('IPv6: ${device.ipv6Public.first}'),
            if (device.ipv4Tailscale.isNotEmpty)
              Text('TS: ${device.ipv4Tailscale.first}'),
            if (device.ipv4Lan.isNotEmpty)
              Text('LAN: ${device.ipv4Lan.first}'),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () => _connectToDevice(device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设备'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('错误: $_error'))
              : _devices.isEmpty
                  ? const Center(child: Text('暂无可用设备'))
                  : ListView(
                      children: _devices.map(_buildDeviceCard).toList(),
                    ),
    );
  }
}
