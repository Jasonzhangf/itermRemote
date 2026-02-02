import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iterm2_host/config/host_config.dart';

import '../services/app_controller.dart';

class NetworkPriorityEditor extends StatefulWidget {
  const NetworkPriorityEditor({super.key});

  @override
  State<NetworkPriorityEditor> createState() => _NetworkPriorityEditorState();
}

class _NetworkPriorityEditorState extends State<NetworkPriorityEditor> {
  late List<NetworkEndpointType> _localPriority;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppController>().config;
    _localPriority = (cfg?.networkPriority ?? []).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppController>();
    final cfg = ctrl.config;
    final priority = cfg?.networkPriority ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Network Priority',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                  'Drag to reorder',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: _onReorder,
              children: [
                for (final type in _localPriority)
                  ListTile(
                    key: ValueKey(type),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(_label(type)),
                    subtitle: Text(_description(type),
                        style: const TextStyle(fontSize: 12)),
                    trailing: _icon(type),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final current = ctrl.config;
                if (current == null) return;
                final next = current.copyWith(networkPriority: _localPriority);
                await ctrl.save(next);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Priority saved')),
                );
              },
              icon: const Icon(Icons.save),
              label: const Text('Save Priority Order'),
            ),
          ],
        ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = _localPriority.removeAt(oldIndex);
    _localPriority.insert(newIndex, item);
    setState(() {});
  }

  String _label(NetworkEndpointType type) {
    switch (type) {
      case NetworkEndpointType.ipv6:
        return 'IPv6 (Cached Direct)';
      case NetworkEndpointType.tailscale:
        return 'Tailscale';
      case NetworkEndpointType.lanIpv4:
        return 'LAN IPv4';
      case NetworkEndpointType.turn:
        return 'TURN Relay';
    }
  }

  String _description(NetworkEndpointType type) {
    switch (type) {
      case NetworkEndpointType.ipv6:
        return 'Direct connection using cached IPv6 address';
      case NetworkEndpointType.tailscale:
        return 'Tailscale mesh network (v6/v4)';
      case NetworkEndpointType.lanIpv4:
        return 'Local area network IPv4';
      case NetworkEndpointType.turn:
        return 'TURN relay server (last resort)';
    }
  }

  Widget _icon(NetworkEndpointType type) {
    switch (type) {
      case NetworkEndpointType.ipv6:
        return const Icon(Icons.wifi, color: Colors.green);
      case NetworkEndpointType.tailscale:
        return const Icon(Icons.vpn_key, color: Colors.blue);
      case NetworkEndpointType.lanIpv4:
        return const Icon(Icons.router, color: Colors.orange);
      case NetworkEndpointType.turn:
        return const Icon(Icons.cloud, color: Colors.grey);
    }
  }
}

