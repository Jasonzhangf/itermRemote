import "package:flutter/material.dart";
import "../../services/auth_service.dart";
import "../../services/device_service.dart";
import "../../pages/network_info_page.dart";

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  List<DeviceInfo> _devices = [];
  DeviceInfo? _localDevice;
  bool _loadingDevices = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      await DeviceService.instance.reportDeviceStatus(isOnline: true);
      
      final devices = await DeviceService.instance.getDevices();
      final localId = DeviceService.instance.getLocalDeviceId();
      
      DeviceInfo? local;
      try {
        local = devices.firstWhere((d) => d.deviceId == localId);
      } catch (_) {
        local = null;
      }
      
      final others = devices.where((d) => d.deviceId != localId).toList();
      
      setState(() {
        _localDevice = local;
        _devices = others;
        _loadingDevices = false;
      });
    } catch (e) {
      setState(() => _loadingDevices = false);
    }
  }

  Widget _buildAddressChip(String label, String ip, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        "$label: $ip",
        style: TextStyle(fontSize: 10, color: color, fontFamily: "monospace"),
      ),
    );
  }

  Widget _buildAddressList(DeviceInfo d) {
    final List<Widget> addresses = [];
    
    for (final ip in d.ipv6Public) {
      addresses.add(_buildAddressChip("IPv6", ip, Colors.blue));
    }
    for (final ip in d.ipv4Tailscale) {
      addresses.add(_buildAddressChip("TS", ip, Colors.purple));
    }
    for (final ip in d.ipv4Lan) {
      addresses.add(_buildAddressChip("LAN", ip, Colors.green));
    }
    
    if (addresses.isEmpty) {
      return const Text("无地址", style: TextStyle(fontSize: 11, color: Colors.grey));
    }
    
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: addresses,
    );
  }

  Widget _buildDeviceCard(DeviceInfo d, {bool isLocal = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isLocal ? Colors.blue.shade900.withOpacity(0.3) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, size: 18, color: isLocal ? Colors.blue.shade300 : null),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${d.deviceName.isEmpty ? d.deviceId : d.deviceName}${isLocal ? " (本机)" : ""}",
                    style: TextStyle(
                      fontSize: 13, 
                      fontWeight: FontWeight.bold,
                      color: isLocal ? Colors.blue.shade100 : null,
                    ),
                  ),
                ),
                if (d.isOnline)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _buildAddressList(d),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.account_circle, size: 48),
                const SizedBox(height: 8),
                Text(
                  AuthService.instance.currentUser?["username"] ?? "未登录",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  AuthService.instance.currentUser?["role"] ?? "",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_localDevice != null) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              "本机",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          _buildDeviceCard(_localDevice!, isLocal: true),
          const Divider(),
        ],

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            "其他设备",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        if (_loadingDevices)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_devices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("暂无其他设备", style: TextStyle(color: Colors.grey)),
          )
        else
          ..._devices.map((d) => _buildDeviceCard(d)),

        ListTile(
          leading: const Icon(Icons.refresh, size: 20),
          title: const Text("刷新设备列表", style: TextStyle(fontSize: 13)),
          onTap: _loadDevices,
        ),

        const Divider(),

        ListTile(
          leading: const Icon(Icons.network_check),
          title: const Text("网络信息"),
          subtitle: const Text("查看本机 IPv4/IPv6 地址"),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NetworkInfoPage()),
            );
          },
        ),

        const Divider(),

        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text("登出"),
          onTap: () async {
            await AuthService.instance.logout();
          },
        ),
      ],
    );
  }
}
