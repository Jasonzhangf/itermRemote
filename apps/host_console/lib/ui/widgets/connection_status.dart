import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../logic/app_state.dart';
import '../theme.dart';

/// Connection status widget with connect/disconnect button
class DaemonConnectionStatus extends StatelessWidget {
  const DaemonConnectionStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final isConnected = state.isConnected;
        final isLoading = state.isLoadingPanels;
        final error = state.errorMessage;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isConnected ? AppTheme.statusSuccess.withOpacity(0.1) : AppTheme.statusError.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isConnected ? AppTheme.statusSuccess : AppTheme.statusError,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    isConnected ? Icons.check_circle : Icons.error_outline,
                    color: isConnected ? AppTheme.statusSuccess : AppTheme.statusError,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isConnected ? 'Connected to Daemon' : 'Disconnected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isConnected ? AppTheme.statusSuccess : AppTheme.statusError,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isConnected ? state.disconnect : state.connect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? AppTheme.statusError : AppTheme.accentRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(isConnected ? 'Disconnect' : 'Connect'),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: const TextStyle(
                    color: AppTheme.statusError,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: state.clearError,
                  child: const Text(
                    'Dismiss',
                    style: TextStyle(
                      color: AppTheme.accentRed,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
              if (isConnected) ...[
                const SizedBox(height: 8),
                Text(
                  '${state.panels.length} panels available',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
