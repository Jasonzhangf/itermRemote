import 'package:flutter/material.dart';

/// Floating control overlay for streaming page.
class ControlOverlay extends StatelessWidget {
  final VoidCallback onToggleKeyboard;
  final VoidCallback onToggleControlBar;

  const ControlOverlay({
    super.key,
    required this.onToggleKeyboard,
    required this.onToggleControlBar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(
            icon: Icons.keyboard,
            label: 'Keyboard',
            onTap: onToggleKeyboard,
          ),
          const Divider(height: 8),
          _ControlButton(
            icon: Icons.mouse,
            label: 'Mouse',
            onTap: () {},
          ),
          const Divider(height: 8),
          _ControlButton(
            icon: Icons.gesture,
            label: 'Gestures',
            onTap: () {},
          ),
          const Divider(height: 8),
          _ControlButton(
            icon: Icons.settings,
            label: 'Hide',
            onTap: onToggleControlBar,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurface),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
