import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';

class AdvancedPage extends StatelessWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              children: const [
                _RecoveryPolicySection(),
                SizedBox(height: 24),
                _SimulationSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryPolicySection extends StatelessWidget {
  const _RecoveryPolicySection();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recovery Policy',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _kv('Throttle Interval', '1800 ms'),
            _kv('Min Background for Kick', '8000 ms'),
            _kv('Backoff Schedule', '5s → 9s → 26s'),
            _kv('First Attempt', 'Prefer cached IPv6'),
            const SizedBox(height: 12),
            const Text(
              'Note: These parameters are currently read-only. '
              'Edit them in code or wait for future UI.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(k, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

class _SimulationSection extends StatelessWidget {
  const _SimulationSection();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppController>();
    final cfg = ctrl.config;
    final enabled = cfg?.enableSimulation ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Simulation Mode',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Enable Local Simulation'),
              subtitle: const Text('Use FakeSignalingTransport and FakePeerConnection'),
              value: enabled,
              onChanged: (v) async {
                final current = ctrl.config;
                if (current == null) return;
                final next = current.copyWith(enableSimulation: v);
                await ctrl.save(next);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Simulation mode setting saved')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

