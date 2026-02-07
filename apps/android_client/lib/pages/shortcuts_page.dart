import 'package:flutter/material.dart';

/// Shortcuts page - 收藏当前连接的窗口和 Panel 快捷
///
/// 功能：
/// - 显示当前连接的主机窗口列表
/// - 显示当前 iTerm2 的 Panel 列表
/// - 收藏常用窗口/Panel 作为快捷切换
/// - 快速切换目标
class ShortcutsPage extends StatefulWidget {
  const ShortcutsPage({super.key});

  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  String _selectedCategory = 'Panels';

  // 模拟当前连接的窗口和 Panel 数据
  // 实际应该从 WebSocket 获取
  final List<PanelItem> _panels = [
    PanelItem(id: 'panel-1', name: 'Terminal 1', isActive: true),
    PanelItem(id: 'panel-2', name: 'Terminal 2', isActive: false),
    PanelItem(id: 'panel-3', name: 'vim main.dart', isActive: false),
    PanelItem(id: 'panel-4', name: 'git status', isActive: false),
  ];
  
  final List<WindowItem> _windows = [
    WindowItem(id: 'win-1', name: 'iTerm2', type: 'app'),
    WindowItem(id: 'win-2', name: 'Chrome', type: 'app'),
    WindowItem(id: 'win-3', name: 'VS Code', type: 'app'),
    WindowItem(id: 'screen-1', name: 'Desktop', type: 'screen'),
  ];
  
  // 收藏的快捷
  final List<FavoriteItem> _favorites = [
    FavoriteItem(id: 'fav-1', name: 'Main Terminal', targetId: 'panel-1', type: 'panel'),
    FavoriteItem(id: 'fav-2', name: 'Browser', targetId: 'win-2', type: 'window'),
  ];
  
  final List<String> _categories = ['Panels', 'Windows', 'Favorites'];

  void _switchToTarget(String targetId, String type) {
    // TODO: 通过 WebSocket 发送切换指令
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Switching to $type: $targetId')),
    );
  }
  
  void _addToFavorites(String name, String targetId, String type) {
    setState(() {
      _favorites.add(FavoriteItem(
        id: 'fav-${_favorites.length + 1}',
        name: name,
        targetId: targetId,
        type: type,
      ));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to favorites')),
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
      appBar: AppBar(
        title: const Text('Quick Switch'),
      ),
      body: Column(
        children: [
          // Category selector
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categories.map((category) {
                final isSelected = category == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _selectedCategory = category);
                    },
                    backgroundColor: theme.colorScheme.surface,
                    selectedColor: theme.colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          // Content based on category
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContent() {
    switch (_selectedCategory) {
      case 'Panels':
        return _buildPanelList();
      case 'Windows':
        return _buildWindowList();
      case 'Favorites':
        return _buildFavoritesList();
      default:
        return const Center(child: Text('Select a category'));
    }
  }
  
  Widget _buildPanelList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _panels.length,
      itemBuilder: (context, index) {
        final panel = _panels[index];
        return _TargetCard(
          title: panel.name,
          subtitle: panel.isActive ? 'Active' : 'Inactive',
          icon: Icons.terminal,
          isActive: panel.isActive,
          onTap: () => _switchToTarget(panel.id, 'panel'),
          onFavorite: () => _addToFavorites(panel.name, panel.id, 'panel'),
        );
      },
    );
  }
  
  Widget _buildWindowList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _windows.length,
      itemBuilder: (context, index) {
        final window = _windows[index];
        return _TargetCard(
          title: window.name,
          subtitle: window.type == 'screen' ? 'Screen' : 'Window',
          icon: window.type == 'screen' ? Icons.desktop_windows : Icons.app_shortcut,
          onTap: () => _switchToTarget(window.id, 'window'),
          onFavorite: () => _addToFavorites(window.name, window.id, 'window'),
        );
      },
    );
  }
  
  Widget _buildFavoritesList() {
    if (_favorites.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text('No favorites yet', style: TextStyle(color: Colors.white54)),
            SizedBox(height: 8),
            Text('Tap star to add favorites', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final fav = _favorites[index];
        return _TargetCard(
          title: fav.name,
          subtitle: fav.type.toUpperCase(),
          icon: fav.type == 'panel' ? Icons.terminal : Icons.app_shortcut,
          isFavorite: true,
          onTap: () => _switchToTarget(fav.targetId, fav.type),
          onDelete: () => _removeFavorite(fav.id),
        );
      },
    );
  }
}

class PanelItem {
  final String id;
  final String name;
  final bool isActive;
  
  PanelItem({required this.id, required this.name, this.isActive = false});
}

class WindowItem {
  final String id;
  final String name;
  final String type;
  
  WindowItem({required this.id, required this.name, required this.type});
}

class FavoriteItem {
  final String id;
  final String name;
  final String targetId;
  final String type;
  
  FavoriteItem({
    required this.id,
    required this.name,
    required this.targetId,
    required this.type,
  });
}

class _TargetCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final VoidCallback? onDelete;
  
  const _TargetCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isActive = false,
    this.isFavorite = false,
    required this.onTap,
    this.onFavorite,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isActive ? theme.colorScheme.primary.withOpacity(0.2) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive 
                    ? theme.colorScheme.primary 
                    : theme.colorScheme.onSurface.withOpacity(0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7),
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isActive ? theme.colorScheme.primary : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onFavorite != null)
                  IconButton(
                    icon: const Icon(Icons.star_border),
                    onPressed: onFavorite,
                    tooltip: 'Add to favorites',
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                    tooltip: 'Remove',
                  ),
                if (isActive)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
