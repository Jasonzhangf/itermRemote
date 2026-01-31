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
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.filter_center_focus),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: _selected,
              isExpanded: true,
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
        ],
      ),
    );
  }
}

