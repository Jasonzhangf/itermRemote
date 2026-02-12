import 'package:flutter/material.dart';

/// Panel/capture target switcher placeholder.
///
/// Future phases will list iTerm2 sessions, windows, screens, etc.
class PanelSwitcher extends StatefulWidget {
  const PanelSwitcher({super.key});

  @override
  State<PanelSwitcher> createState() => _PanelSwitcherState();
}

class _PanelSwitcherState extends State<PanelSwitcher> {
  String _selected = 'iTerm2 Panel';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.filter_center_focus, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.2)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selected,
                  isExpanded: true,
                  dropdownColor: theme.colorScheme.surface,
                  items: const [
                    DropdownMenuItem(
                      value: 'iTerm2 Panel',
                      child: Text('iTerm2 Panel'),
                    ),
                    DropdownMenuItem(
                      value: 'Window',
                      child: Text('Window'),
                    ),
                    DropdownMenuItem(
                      value: 'Screen',
                      child: Text('Screen'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selected = v;
                    });
                    // TODO: call host to switch capture target.
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh panels',
            onPressed: () {},
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
