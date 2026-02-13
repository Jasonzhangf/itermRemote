import 'package:flutter/material.dart';
import '../services/connection_service.dart';
import '../services/device_service.dart';
import '../services/remote_ws_service.dart';
import 'streaming_page.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  List<DeviceInfo> _devices = [];
  bool _loading = false;
  bool _connecting = false;
  String? _error;
  String? _connectionMode; // 'direct' or 'relay'

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _loading = true);
    try {
      // 确保 RemoteWS 已连接以获取设备列表
      if (!RemoteWsService.instance.isConnected) {
        await RemoteWsService.instance.connect();
      }
      final devices = await DeviceService.instance.getDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 显示连接模式选择对话框
  Future<void> _showConnectionModeSelector(DeviceInfo device, int ipCount, bool hasRelay) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('连接方式 - ${device.deviceName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ipCount > 0)
              ListTile(
                leading: const Icon(Icons.wifi, color: Colors.green),
                title: const Text('直接连接 (LAN/P2P)'),
                subtitle: Text('$ipCount 个可用地址'),
                onTap: () => Navigator.of(ctx).pop('direct'),
              ),
            if (hasRelay)
              ListTile(
                leading: const Icon(Icons.cloud, color: Colors.blue),
                title: const Text('中继服务器 (Relay)'),
                subtitle: const Text('通过服务器转发'),
                onTap: () => Navigator.of(ctx).pop('relay'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (mode == 'relay') {
      await _connectViaRelay(device);
    } else if (mode == 'direct') {
      if (ipCount > 1) {
        await _showIpSelector(device);
      } else {
        await _connectWithAutoIp(device);
      }
    }
  }

  /// 通过 relay 连接
  Future<void> _connectViaRelay(DeviceInfo device) async {
    setState(() {
      _connecting = true;
      _connectionMode = 'relay';
    });
    try {
      print('[Connect] Connecting via relay to ${device.deviceId}');
      await ConnectionService.instance.connectViaRelay(hostDeviceId: device.deviceId);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StreamingPage(hostName: device.deviceName),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Relay connection failed: $e';
        _connecting = false;
        _connectionMode = null;
      });
    }
  }

  /// 自动选择 IP 连接
  Future<void> _connectWithAutoIp(DeviceInfo device) async {
    setState(() => _connecting = true);
    try {
      String ip = device.ipv6Public.isNotEmpty
          ? device.ipv6Public.first
          : device.ipv4Tailscale.isNotEmpty
              ? device.ipv4Tailscale.first
              : device.ipv4Lan.isNotEmpty
                  ? device.ipv4Lan.first
                  : '127.0.0.1';

      print('[Connect] Connecting to ${device.deviceId} at $ip:8766');

      await ConnectionService.instance.connect(
        hostId: device.deviceId,
        hostIp: ip,
        port: 8766,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StreamingPage(hostName: device.deviceName),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Connection failed: $e';
        _connecting = false;
      });
    }
  }

  /// 显示 IP 选择对话框
  Future<void> _showIpSelector(DeviceInfo device) async {
    final allIps = <_IpOption>[];
    
    for (final ip in device.ipv6Public) {
      allIps.add(_IpOption(ip: ip, type: 'IPv6', priority: 0, icon: Icons.public));
    }
    for (final ip in device.ipv4Tailscale) {
      allIps.add(_IpOption(ip: ip, type: 'Tailscale', priority: 1, icon: Icons.vpn_lock));
    }
    for (final ip in device.ipv4Lan) {
      allIps.add(_IpOption(ip: ip, type: 'LAN', priority: 2, icon: Icons.wifi));
    }
    
    if (allIps.isEmpty) {
      setState(() => _error = 'No available IP addresses');
      return;
    }
    
    final selected = await showDialog<_IpOption>(
      context: context,
      builder: (ctx) => _IpSelectorDialog(options: allIps, deviceName: device.deviceName),
    );
    
    if (selected != null) {
      await _connectWithIp(device, selected.ip);
    }
  }

  Future<void> _connectWithIp(DeviceInfo device, String ip) async {
    setState(() => _connecting = true);
    try {
      print('[Connect] Connecting to ${device.deviceId} at $ip:8766');

      await ConnectionService.instance.connect(
        hostId: device.deviceId,
        hostIp: ip,
        port: 8766,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StreamingPage(hostName: device.deviceName),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Connection failed: $e';
        _connecting = false;
      });
    }
  }

  Future<void> _connectToDevice(DeviceInfo device) async {
    final ipCount = device.ipv6Public.length + device.ipv4Tailscale.length + device.ipv4Lan.length;
    final hasRelay = device.isOnline && RemoteWsService.instance.isConnected;
    
    if (ipCount > 1 || hasRelay) {
      await _showConnectionModeSelector(device, ipCount, hasRelay);
      return;
    }
    
    // 单个 IP 直接连接
    await _connectWithAutoIp(device);
  }

  Future<void> _connectLocalLoopback() async {
    setState(() => _connecting = true);
    try {
      print('[Connect] Connecting to local loopback (127.0.0.1:8766)');

      await ConnectionService.instance.connect(
        hostId: 'localhost',
        hostIp: '127.0.0.1',
        port: 8766,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const StreamingPage(hostName: 'Local Loopback'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Local connection failed: $e';
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Host'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  child: ListTile(
                    leading: const Icon(Icons.computer, color: Colors.green),
                    title: const Text('Local Loopback Test'),
                    subtitle: const Text('127.0.0.1:8766 - Direct daemon connection'),
                    trailing: _connecting
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _connecting ? null : _connectLocalLoopback,
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _devices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.devices_other, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text('No devices found', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loadDevices,
                                child: const Text('Refresh'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            final ipCount = device.ipv6Public.length + device.ipv4Tailscale.length + device.ipv4Lan.length;
                            final hasRelay = device.isOnline && RemoteWsService.instance.isConnected;
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: Icon(
                                  Icons.computer,
                                  color: device.isOnline ? Colors.green : Colors.grey,
                                ),
                                title: Text(device.deviceName),
                                subtitle: Text(
                                  'IPv6: ${device.ipv6Public.isNotEmpty ? device.ipv6Public.first : 'N/A'}\n'
                                  'TS: ${device.ipv4Tailscale.isNotEmpty ? device.ipv4Tailscale.first : 'N/A'}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                isThreeLine: true,
                                trailing: _connecting
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (ipCount > 1) ...[
                                            Icon(Icons.list, size: 16, color: Colors.grey[600]),
                                            const SizedBox(width: 8),
                                          ],
                                          if (hasRelay)
                                            const Icon(Icons.cloud, size: 16, color: Colors.blue),
                                          const Icon(Icons.arrow_forward_ios, size: 16),
                                        ],
                                      ),
                                onTap: _connecting ? null : () => _connectToDevice(device),
                              ),
                            );
                          },
                        ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
    );
  }
}

class _IpOption {
  final String ip;
  final String type;
  final int priority;
  final IconData icon;
  
  _IpOption({
    required this.ip,
    required this.type,
    required this.priority,
    required this.icon,
  });
}

class _IpSelectorDialog extends StatelessWidget {
  final List<_IpOption> options;
  final String deviceName;
  
  const _IpSelectorDialog({
    required this.options,
    required this.deviceName,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Select IP for $deviceName'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (ctx, index) {
            final opt = options[index];
            return ListTile(
              leading: Icon(opt.icon, color: opt.priority == 0 ? Colors.green : null),
              title: Text(opt.ip),
              subtitle: Text(opt.type),
              trailing: opt.priority == 0 
                  ? const Icon(Icons.star, color: Colors.amber, size: 16)
                  : null,
              onTap: () => Navigator.of(context).pop(opt),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
