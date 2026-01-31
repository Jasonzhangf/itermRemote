import 'package:flutter/material.dart';

/// Connection page for device discovery and host selection.
///
/// In Phase-3, this is a placeholder with basic UI structure.
/// Future phases will add actual device discovery logic.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  /// List of discovered hosts (placeholder).
  final List<Map<String, String>> _discoveredHosts = [
    {'id': 'host-1', 'name': 'MacBook Pro', 'ip': '192.168.1.100'},
    {'id': 'host-2', 'name': 'iMac', 'ip': '192.168.1.101'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Host'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // TODO: Implement host discovery refresh.
            },
          ),
        ],
      ),
      body: _discoveredHosts.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Searching for hosts...'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _discoveredHosts.length,
              itemBuilder: (context, index) {
                final host = _discoveredHosts[index];
                return ListTile(
                  leading: const Icon(Icons.computer),
                  title: Text(host['name'] ?? 'Unknown'),
                  subtitle: Text(host['ip'] ?? ''),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Navigate to streaming page with selected host.
                    Navigator.of(context).pushNamed('/streaming');
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Implement manual host connection.
        },
        label: const Text('Add Host'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
