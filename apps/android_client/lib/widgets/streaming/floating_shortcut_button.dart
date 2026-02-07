import 'package:flutter/material.dart';

/// 悬浮快捷键按钮 - 固定在右下角
/// 
/// 参考 cloudplayplus_stone 设计：
/// - 点击展开工具栏
/// - 工具栏包含流控制、方向键、自定义快捷键
/// - 完全悬浮，不占底部导航
class FloatingShortcutButton extends StatefulWidget {
  const FloatingShortcutButton({super.key});

  @override
  State<FloatingShortcutButton> createState() => _FloatingShortcutButtonState();
}

class _FloatingShortcutButtonState extends State<FloatingShortcutButton> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Stack(
      children: [
        // 展开的工具栏
        if (_isExpanded)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ShortcutToolbar(
              onClose: () => setState(() => _isExpanded = false),
            ),
          ),
        
        // 悬浮按钮
        if (!_isExpanded)
          Positioned(
            right: 16,
            bottom: 16,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                onTap: () => setState(() => _isExpanded = true),
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.keyboard,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 快捷键工具栏
class _ShortcutToolbar extends StatelessWidget {
  final VoidCallback onClose;

  const _ShortcutToolbar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      elevation: 16,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 流控制行
                _StreamControlRow(onClose: onClose),
                const SizedBox(height: 12),
                
                // 快捷键区域
                SizedBox(
                  height: 80,
                  child: Row(
                    children: [
                      // 方向键组
                      _ArrowKeysGroup(),
                      const SizedBox(width: 12),
                      
                      // 自定义快捷键（横向滚动）
                      Expanded(
                        child: _CustomShortcutsBar(),
                      ),
                    ],
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

/// 流控制行
class _StreamControlRow extends StatelessWidget {
  final VoidCallback onClose;

  const _StreamControlRow({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 模式选择
        _ControlButton(
          icon: Icons.desktop_windows,
          label: 'Desktop',
          onTap: () {
            // TODO: 切换到 Desktop 模式
          },
        ),
        const SizedBox(width: 8),
        
        // 目标选择
        _ControlButton(
          icon: Icons.filter_center_focus,
          label: 'Target',
          onTap: () {
            // TODO: 打开目标选择器
          },
        ),
        const SizedBox(width: 8),
        
        // IME 策略
        _ControlButton(
          icon: Icons.text_fields,
          label: 'IME',
          onTap: () {
            // TODO: IME 设置
          },
        ),
        
        const Spacer(),
        
        // 关闭按钮
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onClose,
          color: Colors.white70,
          iconSize: 20,
        ),
      ],
    );
  }
}

/// 方向键组
class _ArrowKeysGroup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 80,
      child: Stack(
        children: [
          // 上
          Positioned(
            top: 0,
            left: 40,
            child: _ArrowButton(
              icon: Icons.arrow_drop_up,
              onTap: () {
                // TODO: Send Arrow Up
              },
            ),
          ),
          // 左
          Positioned(
            top: 30,
            left: 0,
            child: _ArrowButton(
              icon: Icons.arrow_left,
              onTap: () {
                // TODO: Send Arrow Left
              },
            ),
          ),
          // 右
          Positioned(
            top: 30,
            right: 0,
            child: _ArrowButton(
              icon: Icons.arrow_right,
              onTap: () {
                // TODO: Send Arrow Right
              },
            ),
          ),
          // 下
          Positioned(
            bottom: 0,
            left: 40,
            child: _ArrowButton(
              icon: Icons.arrow_drop_down,
              onTap: () {
                // TODO: Send Arrow Down
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义快捷键条
class _CustomShortcutsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shortcuts = [
      ('⌘C', 'Copy'),
      ('⌘V', 'Paste'),
      ('⌘Z', 'Undo'),
      ('⌘Tab', 'Switch'),
      ('F5', 'Refresh'),
      ('Esc', 'Escape'),
    ];

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: shortcuts.length,
      itemBuilder: (context, index) {
        final (keys, label) = shortcuts[index];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _ShortcutChip(
            keys: keys,
            label: label,
            onTap: () {
              // TODO: Send shortcut
            },
          ),
        );
      },
    );
  }
}

/// 控制按钮
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 方向键按钮
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

/// 快捷键芯片
class _ShortcutChip extends StatelessWidget {
  final String keys;
  final String label;
  final VoidCallback onTap;

  const _ShortcutChip({
    required this.keys,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                keys,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
