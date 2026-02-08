import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:iterm2_host/config/host_config.dart';

import '../services/app_controller.dart';
import '../services/auth_service.dart';
import '../widgets/network_priority_editor.dart';
import '../widgets/turn_config_editor.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _accountId;
  late TextEditingController _stableId;
  late TextEditingController _serverUrl;
  late TextEditingController _logLevel;
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    final cfg = context.read<AppController>().config;
    _accountId = TextEditingController(text: cfg?.accountId ?? 'acc');
    _stableId = TextEditingController(text: cfg?.stableId ?? 'stable');
    _serverUrl = TextEditingController(text: cfg?.signalingServerUrl ?? '');
    _logLevel = TextEditingController(text: cfg?.logLevel ?? 'info');
    _user = AuthService.instance.currentUser;
  }

  @override
  void dispose() {
    _accountId.dispose();
    _stableId.dispose();
    _serverUrl.dispose();
    _logLevel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  if (_user != null) ...[
                    const Text('Account',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("用户名: ${_user!['username'] ?? '-'}"),
                          Text("邮箱: ${_user!['email'] ?? '-'}"),
                          Text("角色: ${_user!['role'] ?? '-'}"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () async {
                          await AuthService.instance.logout();
                          if (!mounted) return;
                          Navigator.of(context).pop();
                        },
                        child: const Text('Logout'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  const Text('Account & Device',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _accountId,
                    decoration: const InputDecoration(
                      labelText: 'Account ID',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _stableId,
                    decoration: const InputDecoration(
                      labelText: 'Stable ID',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'required'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  const Text('Network / Server',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _serverUrl,
                    decoration: const InputDecoration(
                      labelText: 'Signaling Server URL (wss/https)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _logLevel,
                    decoration: const InputDecoration(
                      labelText: 'Log Level',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const NetworkPriorityEditor(),
                  const SizedBox(height: 24),
                  const TurnConfigEditor(),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          final current = ctrl.config;
                          final next = (current ?? HostConfig(
                                accountId: 'acc',
                                stableId: 'stable',
                                signalingServerUrl: '',
                              ))
                              .copyWith(
                            accountId: _accountId.text.trim(),
                            stableId: _stableId.text.trim(),
                            signalingServerUrl: _serverUrl.text.trim(),
                            logLevel: _logLevel.text.trim(),
                          );
                          await ctrl.save(next);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Saved')),
                          );
                        },
                        child: const Text('Save'),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Device ID: ${ctrl.deviceIdString}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
