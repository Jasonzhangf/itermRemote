import 'package:flutter/material.dart';
import '../theme.dart';
import '../pages/settings_page.dart';

/// Top toolbar with connection info and controls
class Toolbar extends StatelessWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        gradient: AppTheme.headerGradient,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Logo/Brand
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text(
                      'R',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'iTermRemote',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          
          const VerticalDivider(width: 1, color: AppTheme.divider),
          
          // Connection status
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildStatusDot(true),
                  const SizedBox(width: 8),
                  const Text(
                    'Mac Studio (Local)',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'localhost:8765',
                      style: TextStyle(
                        color: AppTheme.accentRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _buildIconButton(
                  Icons.settings_outlined,
                  'Settings',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                ),
                _buildIconButton(Icons.fullscreen_outlined, 'Fullscreen'),
                _buildIconButton(Icons.more_vert, 'More'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(bool connected) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: connected ? AppTheme.statusSuccess : AppTheme.statusError,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (connected ? AppTheme.statusSuccess : AppTheme.statusError).withOpacity(0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, {VoidCallback? onTap}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              icon,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
