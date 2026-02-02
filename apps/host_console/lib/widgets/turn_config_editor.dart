import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iterm2_host/config/host_config.dart';

import '../services/app_controller.dart';

class TurnConfigEditor extends StatefulWidget {
  const TurnConfigEditor({super.key});

  @override
  State<TurnConfigEditor> createState() => _TurnConfigEditorState();
}

class _TurnConfigEditorState extends State<TurnConfigEditor> {
  final _uriController = TextEditingController();
  final _usernameController = TextEditingController();
  final _credentialController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppController>().config;
    final turn = cfg?.turn;
    _uriController.text = turn?.uri ?? '';
    _usernameController.text = turn?.username ?? '';
    _credentialController.text = turn?.credential ?? '';
  }

  @override
  void dispose() {
    _uriController.dispose();
    _usernameController.dispose();
    _credentialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppController>();
    final cfg = ctrl.config;
    final turn = cfg?.turn;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('TURN Server',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: turn != null,
                  onChanged: (v) async {
                    final current = ctrl.config;
                    if (current == null) return;
                    final next = v
                        ? current.copyWith(
                            turn: TurnConfig(
                              uri: _uriController.text.trim(),
                              username: _usernameController.text.trim(),
                              credential: _credentialController.text.trim(),
                            ),
                          )
                        : current.copyWith(turn: null);
                    await ctrl.save(next);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (turn != null) ...[
              TextFormField(
                controller: _uriController,
                decoration: const InputDecoration(
                  labelText: 'TURN URI (turn:example.com:3478)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _credentialController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Credential',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final current = ctrl.config;
                  if (current == null) return;
                  final next = current.copyWith(
                    turn: TurnConfig(
                      uri: _uriController.text.trim(),
                      username: _usernameController.text.trim(),
                      credential: _credentialController.text.trim(),
                    ),
                  );
                  await ctrl.save(next);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('TURN config saved')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('Save TURN Config'),
              ),
            ] else
              const Text(
                'TURN server is disabled',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

