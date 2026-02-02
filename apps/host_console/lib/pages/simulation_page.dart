import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_controller.dart';
import 'package:iterm2_host/network/connection/connection_orchestrator.dart';

class SimulationPage extends StatelessWidget {
  const SimulationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppController>();
    final events = ctrl.eventLog;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection Simulation'),
        actions: [
          IconButton(
            tooltip: 'Trigger Negotiation Failed',
            onPressed: () async {
              await ctrl.triggerNegotiationFailed();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Orchestrator Event Stream',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: events.isEmpty
                    ? const Center(
                        child: Text(
                          'No events yet. Press Start Simulation to begin.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (ctx, idx) {
                          final line = events[events.length - 1 - idx];
                          return ListTile(
                            dense: true,
                            leading: Icon(_iconForEvent(line)),
                            title: Text(
                              line,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForEvent(String line) {
    if (line.contains('[start]')) return Icons.play_arrow;
    if (line.contains('[resolve]')) return Icons.search;
    if (line.contains('[attempt]')) return Icons.send;
    if (line.contains('[connected]')) return Icons.check_circle;
    if (line.contains('[failed]')) return Icons.error;
    if (line.contains('[recoveryAction]')) return Icons.refresh;
    if (line.contains('[scheduleRetry]')) return Icons.access_time;
    if (line.contains('[stopped]')) return Icons.stop;
    return Icons.info;
  }
}
