import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 悬浮快捷键按钮 - 固定在右下角
/// 
/// 参考 cloudplayplus_stone 设计：
/// - 点击展开工具栏
/// - 工具栏包含流控制、方向键、自定义快捷键
/// - 完全悬浮，不占底部导航
/// - 支持展开/收起动画
class FloatingShortcutButton extends StatefulWidget {
  const FloatingShortcutButton({super.key});

  @override
  State<FloatingShortcutButton> createState() => _FloatingShortcutButtonState();
}

class _FloatingShortcutButtonState extends State<FloatingShortcutButton>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  // 快捷键配置
  final List<_ShortcutConfig> _shortcuts = const [
    _ShortcutConfig(keys: '⌘C', label: 'Copy', keyCode: LogicalKeyboardKey.keyC),
    _ShortcutConfig(keys: '⌘V', label: 'Paste', keyCode: LogicalKeyboardKey.keyV),
    _ShortcutConfig(keys: '⌘Z', label: 'Undo', keyCode: LogicalKeyboardKey.keyZ),
    _ShortcutConfig(keys: '⌘Tab', label: 'Switch', keyCode: LogicalKeyboardKey.tab),
    _ShortcutConfig(keys: 'F5', label: 'Refresh', keyCode: LogicalKeyboardKey.f5),
    _ShortcutConfig(keys: 'Esc', label: 'Escape', keyCode: LogicalKeyboardKey.escape),
    _ShortcutConfig(keys: '⌘A', label: 'Select', keyCode: LogicalKeyboardKey.keyA),
    _ShortcutConfig(keys: '⌘S', label: 'Save', keyCode: LogicalKeyboardKey.keyS),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _sendKeyEvent(LogicalKeyboardKey key, {bool isModifier = false}) {
    // TODO: 集成到 ConnectionService 发送按键事件
    debugPrint('Sending key: ${key.keyId}');
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景遮罩（展开时显示）
        if (_isExpanded)
          GestureDetector(
            onTap: _toggleExpanded,
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),
        
        // 展开的工具栏
        if (_isExpanded)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ShortcutToolbar(
              shortcuts: _shortcuts,
              onClose: _toggleExpanded,
              onShortcutTap: (config) => _sendKeyEvent(config.keyCode),
              animation: _scaleAnimation,
            ),
          ),
        
        // 悬浮按钮
        Positioned(
          right: 16,
          bottom: _isExpanded ? 280 : 16,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                onTap: _toggleExpanded,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _isExpanded 
                        ? Colors.red.withOpacity(0.8)
                        : Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.18),
                      width: 1,
                    ),
                  ),
                  child: AnimatedRotation(
                    turns: _isExpanded ? 0.125 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _isExpanded ? Icons.close : Icons.keyboard,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 快捷键配置
class _ShortcutConfig {
  final String keys;
  final String label;
  final LogicalKeyboardKey keyCode;
  
  const _ShortcutConfig({
    required this.keys,
    required this.label,
    required this.keyCode,
  });
}

/// 快捷键工具栏
class _ShortcutToolbar extends StatelessWidget {
  final List<_ShortcutConfig> shortcuts;
  final VoidCallback onClose;
  final void Function(_ShortcutConfig) onShortcutTap;
  final Animation<double> animation;

  const _ShortcutToolbar({
    required this.shortcuts,
    required this.onClose,
    required this.onShortcutTap,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.scale(
          scale: animation.value,
          alignment: Alignment.bottomCenter,
          child: Opacity(
            opacity: animation.value,
            child: child,
          ),
        );
      },
      child: Material(
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
                  // 拖动条
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // 流控制行
                  _StreamControlRow(onClose: onClose),
                  const SizedBox(height: 16),
                  
                  // 快捷键区域
                  SizedBox(
                    height: 90,
                    child: Row(
                      children: [
                        // 方向键组
                        _ArrowKeysGroup(
                          onUp: () => onShortcutTap(
                            const _ShortcutConfig(
                              keys: '↑', 
                              label: 'Up', 
                              keyCode: LogicalKeyboardKey.arrowUp,
                            ),
                          ),
                          onDown: () => onShortcutTap(
                            const _ShortcutConfig(
                              keys: '↓', 
                              label: 'Down', 
                              keyCode: LogicalKeyboardKey.arrowDown,
                            ),
                          ),
                          onLeft: () => onShortcutTap(
                            const _ShortcutConfig(
                              keys: '←', 
                              label: 'Left', 
                              keyCode: LogicalKeyboardKey.arrowLeft,
                            ),
                          ),
                          onRight: () => onShortcutTap(
                            const _ShortcutConfig(
                              keys: '→', 
                              label: 'Right', 
                              keyCode: LogicalKeyboardKey.arrowRight,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // 自定义快捷键（横向滚动）
                        Expanded(
                          child: _CustomShortcutsBar(
                            shortcuts: shortcuts,
                            onTap: onShortcutTap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
            debugPrint('Switch to Desktop mode');
          },
        ),
        const SizedBox(width: 8),
        
        // 目标选择
        _ControlButton(
          icon: Icons.filter_center_focus,
          label: 'Target',
          onTap: () {
            // TODO: 打开目标选择器
            debugPrint('Open target selector');
          },
        ),
        const SizedBox(width: 8),
        
        // IME 策略
        _ControlButton(
          icon: Icons.text_fields,
          label: 'IME',
          onTap: () {
            // TODO: IME 设置
            debugPrint('Open IME settings');
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
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _ArrowKeysGroup({
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 90,
      child: Stack(
        children: [
          // 上
          Positioned(
            top: 0,
            left: 40,
            child: _ArrowButton(
              icon: Icons.keyboard_arrow_up,
              onTap: onUp,
            ),
          ),
          // 左
          Positioned(
            top: 25,
            left: 0,
            child: _ArrowButton(
              icon: Icons.keyboard_arrow_left,
              onTap: onLeft,
            ),
          ),
          // 右
          Positioned(
            top: 25,
            right: 0,
            child: _ArrowButton(
              icon: Icons.keyboard_arrow_right,
              onTap: onRight,
            ),
          ),
          // 下
          Positioned(
            bottom: 0,
            left: 40,
            child: _ArrowButton(
              icon: Icons.keyboard_arrow_down,
              onTap: onDown,
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义快捷键条
class _CustomShortcutsBar extends StatelessWidget {
  final List<_ShortcutConfig> shortcuts;
  final void Function(_ShortcutConfig) onTap;

  const _CustomShortcutsBar({
    required this.shortcuts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: shortcuts.length,
      itemBuilder: (context, index) {
        final config = shortcuts[index];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _ShortcutChip(
            keys: config.keys,
            label: config.label,
            onTap: () => onTap(config),
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
