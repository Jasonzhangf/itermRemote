import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../logic/app_state.dart';
import '../theme.dart';

/// Settings page - configure connections, stream quality, etc.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Connection Settings
          _buildSection(
            title: 'Connection',
            icon: Icons.wifi,
            children: [
              _buildSettingRow(
                label: 'Host',
                value: state.activeConnection?.host ?? '127.0.0.1',
                onTap: () => _showEditDialog(
                  context,
                  'Host',
                  state.activeConnection?.host ?? '127.0.0.1',
                  (value) {
                    // TODO: Update host
                  },
                ),
              ),
              _buildSettingRow(
                label: 'Port',
                value: '${state.activeConnection?.port ?? 8765}',
                onTap: () => _showEditDialog(
                  context,
                  'Port',
                  '${state.activeConnection?.port ?? 8765}',
                  (value) {
                    // TODO: Update port
                  },
                ),
              ),
              _buildSwitchRow(
                label: 'Auto-connect on startup',
                value: false,
                onChanged: (value) {
                  // TODO: Implement
                },
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Stream Quality
          _buildSection(
            title: 'Stream Quality',
            icon: Icons.high_quality,
            children: [
              _buildSettingRow(
                label: 'Resolution',
                value: '1920×1080',
                onTap: () => _showResolutionDialog(context),
              ),
              _buildSettingRow(
                label: 'Frame Rate',
                value: '30 fps',
                onTap: () => _showFrameRateDialog(context),
              ),
              _buildSettingRow(
                label: 'Bitrate',
                value: '2 Mbps',
                onTap: () => _showBitrateDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // iTerm2 Settings
          _buildSection(
            title: 'iTerm2 Integration',
            icon: Icons.terminal,
            children: [
              _buildSettingRow(
                label: 'Panel refresh rate',
                value: '1.0s',
                onTap: () => _showRefreshDialog(context),
              ),
              _buildSwitchRow(
                label: 'Auto-detect panels',
                value: true,
                onChanged: (value) {
                  // TODO: Implement
                },
              ),
              _buildSwitchRow(
                label: 'Show panel borders',
                value: true,
                onChanged: (value) {
                  // TODO: Implement
                },
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Appearance
          _buildSection(
            title: 'Appearance',
            icon: Icons.palette,
            children: [
              _buildSwitchRow(
                label: 'Dark mode',
                value: true,
                onChanged: (value) {
                  // TODO: Implement theme switching
                },
              ),
              _buildSwitchRow(
                label: 'Show fps overlay',
                value: true,
                onChanged: (value) {
                  // TODO: Implement
                },
              ),
              _buildSwitchRow(
                label: 'Compact mode',
                value: false,
                onChanged: (value) {
                  // TODO: Implement
                },
              ),
            ],
          ),

          const SizedBox(height: 32),

          // About
          _buildSection(
            title: 'About',
            icon: Icons.info_outline,
            children: [
              _buildSettingRow(
                label: 'Version',
                value: 'v0.1.0',
                onTap: null,
              ),
              _buildSettingRow(
                label: 'Build',
                value: 'dev',
                onTap: null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppTheme.accentRedLight),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: onTap != null
                    ? AppTheme.accentRedLight
                    : AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppTheme.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.accentRed,
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String title,
    String currentValue,
    ValueChanged<String> onSave,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          title,
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppTheme.accentRed),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showResolutionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Resolution',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            '1920×1080',
            '1280×720',
            '3840×2160',
          ]
              .map((res) => ListTile(
                    title: Text(
                      res,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    onTap: () {
                      // TODO: Update resolution
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showFrameRateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Frame Rate',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['15', '24', '30', '60']
              .map((fps) => ListTile(
                    title: Text(
                      '$fps fps',
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    onTap: () {
                      // TODO: Update fps
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showBitrateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Bitrate',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['1 Mbps', '2 Mbps', '4 Mbps', '8 Mbps']
              .map((br) => ListTile(
                    title: Text(
                      br,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    onTap: () {
                      // TODO: Update bitrate
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  void _showRefreshDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Panel Refresh Rate',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['0.5s', '1.0s', '2.0s', '5.0s']
              .map((rate) => ListTile(
                    title: Text(
                      rate,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    onTap: () {
                      // TODO: Update refresh rate
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}
