import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "dart:io";
import "dart:async";

class NetworkInfoPage extends StatefulWidget {
  const NetworkInfoPage({super.key});

  @override
  State<NetworkInfoPage> createState() => _NetworkInfoPageState();
}

class _NetworkInfoPageState extends State<NetworkInfoPage> {
  Map<String, dynamic>? _networkInfo;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadNetworkInfo();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadNetworkInfo());
  }

  Future<void> _loadNetworkInfo() async {
    setState(() => _isLoading = true);

    try {
      final interfaces = await NetworkInterface.list(includeLinkLocal: false, includeLoopback: false);

      final ipv4Addrs = <String>[];
      final ipv6Addrs = <String>[];
      final tailscaleAddrs = <String>[];

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final address = addr.address;
          if (addr.type == InternetAddressType.IPv4) {
            if (interface.name.contains("tailscale") ||
                interface.name.contains("ts0") ||
                address.startsWith("100.")) {
              tailscaleAddrs.add(address);
            } else {
              ipv4Addrs.add("${interface.name}: $address");
            }
          } else if (addr.type == InternetAddressType.IPv6) {
            ipv6Addrs.add("${interface.name}: $address");
          }
        }
      }

      setState(() {
        _networkInfo = {
          "ipv4": ipv4Addrs,
          "ipv6": ipv6Addrs,
          "tailscale": tailscaleAddrs,
        };
        _isLoading = false;
      });
    } catch (e) {
      print("[Network] Failed to load: $e");
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("已复制: $text"),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildAddressSection(String title, List<String> addresses, IconData icon) {
    if (addresses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text("无 $title", style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        ...addresses.map((addr) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: InkWell(
                onTap: () => _copyToClipboard(addr.split(": ").last),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          addr,
                          style: const TextStyle(fontFamily: "monospace"),
                        ),
                      ),
                      Icon(Icons.copy, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text(
                        "点击复制",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("网络信息"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNetworkInfo,
            tooltip: "刷新",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_networkInfo != null) ...[
                    _buildAddressSection("IPv6 (公网)", _networkInfo!["ipv6"] ?? [], Icons.public),
                    _buildAddressSection("IPv4 Tailscale", _networkInfo!["tailscale"] ?? [], Icons.vpn_lock),
                    _buildAddressSection("IPv4 局域网", _networkInfo!["ipv4"] ?? [], Icons.lan),
                  ],
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      "提示：点击任意地址可自动复制",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
