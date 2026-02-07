import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/sidebar.dart';
import '../widgets/stream_view.dart';
import '../widgets/panel_selector.dart';
import '../widgets/status_bar.dart';
import '../widgets/toolbar.dart';

/// Main page layout - sidebar | stream | panel selector
/// Fixed proportional layout, no scrolling in main content area.
class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          const Toolbar(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Fixed proportions: 22% left, 78% right (center + right panel)
                final totalW = constraints.maxWidth;
                final leftW = (totalW * 0.22).clamp(200.0, 240.0);
                final centerAndRightW = totalW - leftW - 2; // minus 2 dividers
                final rightW = (centerAndRightW * 0.36).clamp(280.0, 360.0);
                final centerW = centerAndRightW - rightW;

                return Row(
                  children: [
                    SizedBox(width: leftW, child: const Sidebar()),
                    Container(width: 1, color: AppTheme.divider),
                    SizedBox(width: centerW, child: const StreamView()),
                    Container(width: 1, color: AppTheme.divider),
                    SizedBox(width: rightW, child: const PanelSelector()),
                  ],
                );
              },
            ),
          ),
          const StatusBar(),
        ],
      ),
    );
  }
}
