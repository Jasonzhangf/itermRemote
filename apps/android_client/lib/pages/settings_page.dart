import 'package:flutter/material.dart';

/// Settings page.
///
/// Provides:
/// - Connection settings (host, port, auto-reconnect)
/// - Video quality settings
/// - Keyboard layout preferences
/// - About & version info
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _autoReconnect = true;
  double _videoQuality = 2;
  bool _showTouchIndicator = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'Connection'),
          SwitchListTile(
            title: const Text('Auto Reconnect'),
            subtitle: const Text('Reconnect automatically when disconnected'),
            value: _autoReconnect,
            onChanged: (v) => setState(() => _autoReconnect = v),
          ),
          const Divider(height: 24),
          _SectionHeader(title: 'Video'),
          ListTile(
            title: const Text('Video Quality'),
            subtitle: Text(_videoQualityLabel()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: _videoQuality,
              min: 0,
              max: 3,
              divisions: 3,
              label: _videoQualityLabel(),
              onChanged: (v) => setState(() => _videoQuality = v),
            ),
          ),
          const Divider(height: 24),
          _SectionHeader(title: 'Input'),
          SwitchListTile(
            title: const Text('Show Touch Indicator'),
            subtitle: const Text('Show visual feedback for touch events'),
            value: _showTouchIndicator,
            onChanged: (v) => setState(() => _showTouchIndicator = v),
          ),
          const Divider(height: 24),
          _SectionHeader(title: 'About'),
          ListTile(
            title: const Text('Version'),
            subtitle: const Text('1.0.0 (Phase 3)'),
          ),
          ListTile(
            title: const Text('License'),
            subtitle: const Text('MIT License'),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  String _videoQualityLabel() {
    switch (_videoQuality.toInt()) {
      case 0:
        return 'Low';
      case 1:
        return 'Medium';
      case 2:
        return 'High';
      case 3:
        return 'Ultra';
      default:
        return 'High';
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
