import 'package:flutter/material.dart';
import 'connect_page.dart';
import 'streaming_page.dart';
import 'settings_page.dart';
import 'shortcuts_page.dart';
import '../services/connection_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const ConnectPage(),
    const StreamingPage(),
    const ShortcutsPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Auto-switch to Streaming tab when connected
    ConnectionService.instance.connectionState.listen((state) {
      if (state == HostConnectionState.connected && mounted) {
        setState(() => _currentIndex = 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: theme.colorScheme.surface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices),
            label: 'Connect',
          ),
          NavigationDestination(
            icon: Icon(Icons.desktop_mac),
            label: 'Stream',
          ),
          NavigationDestination(
            icon: Icon(Icons.keyboard),
            label: 'Shortcuts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
