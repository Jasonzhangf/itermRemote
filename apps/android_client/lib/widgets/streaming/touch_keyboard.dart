import 'package:flutter/material.dart';

/// On-screen touch keyboard for sending keys to remote host.
class TouchKeyboard extends StatelessWidget {
  final void Function(String key) onKey;

  const TouchKeyboard({
    super.key,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withOpacity(0.98),
        border: Border(
          top: BorderSide(color: theme.colorScheme.onSurface.withOpacity(0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRow(['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'], theme),
            const SizedBox(height: 6),
            _buildRow(['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'], theme),
            const SizedBox(height: 6),
            _buildRow(['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'], theme, padding: const EdgeInsets.symmetric(horizontal: 16)),
            const SizedBox(height: 6),
            _buildRow(['z', 'x', 'c', 'v', 'b', 'n', 'm'], theme, padding: const EdgeInsets.symmetric(horizontal: 32)),
            const SizedBox(height: 6),
            _buildBottomRow(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys, ThemeData theme, {EdgeInsets? padding}) {
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((key) => _KeyButton(
        label: key,
        onTap: () => onKey(key),
      )).toList(),
    );
    return padding != null ? Padding(padding: padding, child: row) : row;
  }

  Widget _buildBottomRow(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          icon: Icons.keyboard_capslock,
          onTap: () {},
          width: 40,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _KeyButton(
            label: 'space',
            onTap: () => onKey(' '),
            flex: 4,
          ),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.backspace,
          onTap: () => onKey('backspace'),
          width: 40,
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.keyboard_return,
          onTap: () => onKey('return'),
          width: 50,
        ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final int flex;

  const _KeyButton({
    required this.label,
    required this.onTap,
    this.flex = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest ?? theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double width;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: width,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}
