import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import 'settings_page.dart';
import 'advanced_page.dart';
import 'simulation_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => context.read<AppController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('iTermRemote Host Console'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              );
            },
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Advanced',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AdvancedPage()),
              );
            },
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Simulation',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SimulationPage()),
              );
            },
            icon: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 360,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _kv('Run State', ctrl.runState.name),
                      _kv('Device ID', ctrl.deviceIdString),
                      _kv('Last Status', ctrl.lastStatus),
                      _kv('Last Attempt', ctrl.lastAttempt == null
                          ? ''
                          : '${ctrl.lastAttempt!.source.name} ${ctrl.lastAttempt!.ipv6}:${ctrl.lastAttempt!.port}'),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: ctrl.runState == HostRunState.starting
                                  ? null
                                  : () => ctrl.startSimulation(),
                              child: const Text('Start Simulation'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: ctrl.runState == HostRunState.stopped
                                ? null
                                : () => ctrl.stop(),
                            child: const Text('Stop'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('IPv6 Address Book',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ctrl.addressBook.records.isEmpty
                            ? const Center(
                                child: Text(
                                  'No cached IPv6 records yet.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.separated(
                                itemCount: ctrl.addressBook.records.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, idx) {
                                  final r = ctrl.addressBook.records[idx];
                                  final updated = DateTime.fromMillisecondsSinceEpoch(
                                      r.updatedAtMs);
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.wifi, color: Colors.green),
                                    title: SelectableText(
                                      r.deviceId,
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                    ),
                                    subtitle: SelectableText(
                                      '${r.ipv6}:${r.port}  •  ${updated.toIso8601String()}',
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
  }
}
