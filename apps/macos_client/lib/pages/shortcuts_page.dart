import 'package:flutter/material.dart';
import '../services/connection_service.dart';

class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  String _selectedCategory = 'Favorites';
  final List<FavoriteItem> _favorites = [];

  final List<String> _categories = ['Favorites'];

  void _switchToTarget(String targetId, String type) {
    if (!ConnectionService.instance.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected to host')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switching to $type: $targetId')),
    );
  }

  void _removeFavorite(String id) {
    setState(() {
      _favorites.removeWhere((f) => f.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Quick Switch')),
      body: !ConnectionService.instance.isConnected
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_off, size: 48, color: Colors.white24),
                  SizedBox(height: 12),
                  Text('Not connected', style: TextStyle(color: Colors.white54)),
                ],
              ),
            )
          : _favorites.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border, size: 48, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('No favorites yet', style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _favorites.length,
                  itemBuilder: (context, index) {
                    final fav = _favorites[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(fav.name),
                        subtitle: Text(fav.type.toUpperCase()),
                        leading: Icon(fav.type == 'panel' ? Icons.terminal : Icons.app_shortcut),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _removeFavorite(fav.id),
                        ),
                        onTap: () => _switchToTarget(fav.targetId, fav.type),
                      ),
                    );
                  },
                ),
    );
  }
}

class FavoriteItem {
  final String id;
  final String name;
  final String targetId;
  final String type;

  FavoriteItem({required this.id, required this.name, required this.targetId, required this.type});
}
