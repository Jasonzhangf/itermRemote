import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../logic/app_state.dart';
import '../../models/connection_model.dart';
import '../theme.dart';

/// Right panel - iTerm2 panel crop mode selector.
/// UI-only for now; will be wired to WS later.
class PanelSelector extends StatelessWidget {
  const PanelSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: 'CAPTURE',
            subtitle: 'Source & iTerm2 panel crop',
            icon: Icons.crop,
          ),
          const Divider(height: 1, color: AppTheme.divider),
          
          // Capture modes
          Padding(
            padding: const EdgeInsets.all(16),
            child: _ModeTabs(
              selected: state.captureMode,
              onSelected: state.setCaptureMode,
            ),
          ),
          
          const Divider(height: 1, color: AppTheme.divider),
          
         // iTerm2 panel list
          Flexible(
            flex: 1,
            fit: FlexFit.loose,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: state.captureMode == CaptureMode.iterm2Panel
                  ? _PanelList(
                      panels: state.panels,
                      selected: state.selectedPanel,
                    onSelect: (panel) async {
                      await state.activatePanel(panel);
                    },
                    )
                  : _NotInPanelMode(mode: state.captureMode),
            ),
          ),
          
          const Divider(height: 1, color: AppTheme.divider),
          
          // Actions
          _BottomActions(
            canRefresh: state.captureMode == CaptureMode.iterm2Panel,
            onRefresh: () {
              state.refreshPanels();
            },
            onSettings: () {},
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final bool canRefresh;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  const _BottomActions({
    required this.canRefresh,
    required this.onRefresh,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    // Fixed-height action area to avoid overflow in narrow/tight layouts.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: canRefresh ? onRefresh : null,
              icon: const Icon(Icons.grid_view, size: 18),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSettings,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Crop'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.accentRed.withOpacity(0.35)),
            ),
            child: Icon(icon, size: 18, color: AppTheme.accentRedLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
            child: const Text('Help'),
          ),
        ],
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  final CaptureMode selected;
  final ValueChanged<CaptureMode> onSelected;

  const _ModeTabs({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Screen',
              icon: Icons.crop_free,
              selected: selected == CaptureMode.screen,
              onTap: () => onSelected(CaptureMode.screen),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Window',
              icon: Icons.window_outlined,
              selected: selected == CaptureMode.window,
              onTap: () => onSelected(CaptureMode.window),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'iTerm2',
              icon: Icons.grid_view,
              selected: selected == CaptureMode.iterm2Panel,
              onTap: () => onSelected(CaptureMode.iterm2Panel),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.surfaceHover : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelList extends StatelessWidget {
  final List<PanelInfo> panels;
  final PanelInfo? selected;
  final ValueChanged<PanelInfo> onSelect;

  const _PanelList({
    required this.panels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (panels.isEmpty) {
      return const Center(
        child: Text(
          'No panels detected',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: panels.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
      itemBuilder: (context, index) {
        final p = panels[index];
        final isSelected = selected?.id == p.id;
        final order = index + 1;

        return Material(
          color: isSelected ? AppTheme.surfaceHover : Colors.transparent,
          child: InkWell(
            onTap: () => onSelect(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // order badge
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppTheme.borderActive : AppTheme.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$order',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? AppTheme.accentRedLight : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              p.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (p.isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.statusSuccess.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.statusSuccess,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          p.detail,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: isSelected ? AppTheme.accentRedLight : AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotInPanelMode extends StatelessWidget {
  final CaptureMode mode;
  const _NotInPanelMode({required this.mode});

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      CaptureMode.screen => 'Screen capture mode',
      CaptureMode.window => 'Window capture mode',
      CaptureMode.iterm2Panel => 'iTerm2 panel mode',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.textMuted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          const Text(
            'Switch to iTerm2 mode to select panels',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
