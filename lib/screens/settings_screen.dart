import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/setting_tile.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';
import '../utils/constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return IconButton(
                  onPressed: () => _showResetDialog(context, settings),
                  icon: const Icon(Icons.restart_alt, size: 20),
                  tooltip: 'Reset to defaults',
                );
              },
            ),
          ],
        ),
        body: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildSection(
                  'Model Settings',
                  [
                    SettingTile(
                      icon: Icons.psychology_rounded,
                      iconColor: AppColors.accent,
                      title: 'System Prompt',
                      subtitle: settings.systemPrompt.length > 50
                          ? '${settings.systemPrompt.substring(0, 50)}...'
                          : settings.systemPrompt,
                      onTap: () => _editSystemPrompt(context, settings),
                    ),
                    SettingTile(
                      icon: Icons.speed_rounded,
                      iconColor: AppColors.success,
                      title: 'Cache Prompts',
                      subtitle: 'Cache prompts to speed up repeated queries',
                      trailing: SettingToggle(
                        value: settings.cachePrompts,
                        onChanged: settings.setCachePrompts,
                      ),
                    ),
                    SettingTile(
                      icon: Icons.stream_rounded,
                      iconColor: AppColors.warning,
                      title: 'Streaming',
                      subtitle: 'Stream tokens as they are generated',
                      trailing: SettingToggle(
                        value: settings.streamingEnabled,
                        onChanged: settings.setStreamingEnabled,
                      ),
                    ),
                  ],
                ),
                _buildSection(
                  'Generation Parameters',
                  [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Temperature',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SettingSlider(
                            value: settings.temperature,
                            min: 0.0,
                            max: 2.0,
                            divisions: 40,
                            labelBuilder: (v) => v.toStringAsFixed(2),
                            onChanged: settings.setTemperature,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Top P',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SettingSlider(
                            value: settings.topP,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            labelBuilder: (v) => v.toStringAsFixed(2),
                            onChanged: settings.setTopP,
                          ),
                        ],
                      ),
                    ),
                    SettingTile(
                      icon: Icons.format_list_numbered_rounded,
                      iconColor: AppColors.primary,
                      title: 'Max Tokens',
                      subtitle: '${settings.maxTokens} tokens',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onTap: () => _editMaxTokens(context, settings),
                    ),
                  ],
                ),
                _buildSection(
                  'RAG Settings',
                  [
                    SettingTile(
                      icon: Icons.search_rounded,
                      iconColor: AppColors.accent,
                      title: 'Enable RAG',
                      subtitle: 'Retrieval-Augmented Generation',
                      trailing: SettingToggle(
                        value: settings.ragEnabled,
                        onChanged: settings.setRagEnabled,
                      ),
                    ),
                    SettingTile(
                      icon: Icons.format_list_numbered_rounded,
                      iconColor: AppColors.primary,
                      title: 'RAG Top-K',
                      subtitle: '${settings.ragTopK} results',
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onTap: () => _editRagTopK(context, settings),
                    ),
                  ],
                ),
                _buildSection(
                  'Cache',
                  [
                    SettingTile(
                      icon: Icons.delete_sweep_rounded,
                      iconColor: AppColors.error,
                      title: 'Clear Prompt Cache',
                      subtitle: 'Remove all cached prompt responses',
                      onTap: () async {
                        await settings.clearPromptCache();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cache cleared'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                _buildSection(
                  'About',
                  [
                    SettingTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: AppColors.textSecondary,
                      title: 'Version',
                      subtitle: AppConstants.appVersion,
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.divider,
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    indent: 66,
                    color: AppColors.divider,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _editSystemPrompt(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(text: settings.systemPrompt);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'System Prompt',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      settings.setSystemPrompt(controller.text);
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Enter system prompt...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editMaxTokens(BuildContext context, SettingsProvider settings) {
    final options = [512, 1024, 2048, 4096, 8192];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Max Tokens',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ...options.map((tokens) {
              final isSelected = settings.maxTokens == tokens;
              return ListTile(
                title: Text(
                  '$tokens',
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  settings.setMaxTokens(tokens);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _editRagTopK(BuildContext context, SettingsProvider settings) {
    final options = [3, 5, 10, 15, 20];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textHint.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'RAG Top-K Results',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ...options.map((k) {
              final isSelected = settings.ragTopK == k;
              return ListTile(
                title: Text(
                  '$k',
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  settings.setRagTopK(k);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all settings to their default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settings.resetToDefaults();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings reset to defaults')),
              );
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}