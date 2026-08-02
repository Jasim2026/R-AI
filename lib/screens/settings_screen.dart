import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/setting_tile.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';
import '../utils/constants.dart';
import 'rag_management_screen.dart';
import 'tool_management_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Settings'),
          actions: [
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                return IconButton(
                  onPressed: () => _showResetDialog(context, settings),
                  icon: Icon(Icons.restart_alt, size: 20),
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
                          Text(
                            'Temperature',
                            style: AppColors.font(
                              color: AppColors.textPrimary,
                              size: 15,
                              weight: FontWeight.w500,
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
                          Text(
                            'Top P',
                            style: AppColors.font(
                              color: AppColors.textPrimary,
                              size: 15,
                              weight: FontWeight.w500,
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
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onTap: () => _editMaxTokens(context, settings),
                    ),
                  ],
                ),
                _buildSection(
                  'RAG',
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
                      icon: Icons.tune_rounded,
                      iconColor: AppColors.primary,
                      title: 'RAG Management',
                      subtitle: 'Embedding models, documents, settings',
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RagManagementScreen(),
                          ),
                        );
                      },
                    ),
                    SettingTile(
                      icon: Icons.swap_horiz_rounded,
                      iconColor: AppColors.warning,
                      title: 'RAG Mode',
                      subtitle: settings.ragMode == 'pre_generation'
                          ? 'Pre-generation (embed before LLM)'
                          : 'Post-generation (LLM checks uncertainty)',
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onTap: () => _editRagMode(context, settings),
                    ),
                    if (settings.ragMode == 'post_generation')
                      SettingTile(
                        icon: Icons.help_outline_rounded,
                        iconColor: AppColors.accent,
                        title: 'Uncertainty Keywords',
                        subtitle: settings.uncertaintyKeywords.length > 40
                            ? '${settings.uncertaintyKeywords.substring(0, 40)}...'
                            : settings.uncertaintyKeywords,
                        onTap: () => _editUncertaintyKeywords(context, settings),
                      ),
                  ],
                ),
                _buildSection(
                  'Tool Calling',
                  [
                    SettingTile(
                      icon: Icons.build_circle_rounded,
                      iconColor: AppColors.warning,
                      title: 'Tool Calling',
                      subtitle: 'Detect and execute tools from responses',
                      trailing: Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                        size: 20,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ToolManagementScreen(),
                          ),
                        );
                      },
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
            style: AppColors.font(
              color: AppColors.textHint,
              size: 11,
              weight: FontWeight.w700,
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SystemPromptEditor(settings: settings),
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
            Text(
              'Max Tokens',
              style: AppColors.font(
                color: AppColors.textPrimary,
                size: 18,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ...options.map((tokens) {
              final isSelected = settings.maxTokens == tokens;
              return ListTile(
                title: Text(
                  '$tokens',
                  style: AppColors.font(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    weight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check, color: AppColors.primary)
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
            Text(
              'RAG Top-K Results',
              style: AppColors.font(
                color: AppColors.textPrimary,
                size: 18,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ...options.map((k) {
              final isSelected = settings.ragTopK == k;
              return ListTile(
                title: Text(
                  '$k',
                  style: AppColors.font(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    weight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check, color: AppColors.primary)
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

  void _editRagMode(BuildContext context, SettingsProvider settings) {
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
            Text(
              'RAG Mode',
              style: AppColors.font(
                color: AppColors.textPrimary,
                size: 18,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pre-generation: Embed query before LLM (faster, always uses RAG)\n'
              'Post-generation: LLM answers first, uses RAG only if uncertain',
              style: AppColors.font(
                color: AppColors.textHint,
                size: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _buildRagModeOption(
              context,
              settings,
              'pre_generation',
              'Pre-generation',
              Icons.search_rounded,
              'Embed before LLM generates',
            ),
            const SizedBox(height: 8),
            _buildRagModeOption(
              context,
              settings,
              'post_generation',
              'Post-generation',
              Icons.refresh_rounded,
              'LLM generates first, RAG on uncertainty',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRagModeOption(
    BuildContext context,
    SettingsProvider settings,
    String value,
    String title,
    IconData icon,
    String subtitle,
  ) {
    final isSelected = settings.ragMode == value;
    return Material(
      color: isSelected
          ? AppColors.primary.withOpacity(0.1)
          : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          settings.setRagMode(value);
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.3)
                  : AppColors.divider,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? AppColors.primary : AppColors.textHint,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppColors.font(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        size: 14,
                        weight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppColors.font(
                        color: AppColors.textHint,
                        size: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: AppColors.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  void _editUncertaintyKeywords(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(text: settings.uncertaintyKeywords);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Uncertainty Keywords',
          style: AppColors.font(color: AppColors.textPrimary, weight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comma-separated keywords that indicate the model is uncertain. '
              'When these appear in a response, RAG will be triggered to re-generate.',
              style: AppColors.font(color: AppColors.textHint, size: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              style: AppColors.font(color: AppColors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              settings.setUncertaintyKeywords(controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text('Save', style: AppColors.font(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Settings'),
        content: Text(
          'Are you sure you want to reset all settings to their default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settings.resetToDefaults();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings reset to defaults')),
              );
            },
            child: Text(
              'Reset',
              style: AppColors.font(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemPromptEditor extends StatefulWidget {
  final SettingsProvider settings;

  const _SystemPromptEditor({required this.settings});

  @override
  State<_SystemPromptEditor> createState() => _SystemPromptEditorState();
}

class _SystemPromptEditorState extends State<_SystemPromptEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.systemPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              color: const Color(0x4D9E9E9E),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'System Prompt',
                    style: AppColors.font(
                      color: AppColors.textPrimary,
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.settings.setSystemPrompt(_controller.text);
                    Navigator.pop(context);
                  },
                  child: Text('Save'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: AppColors.font(
                  color: AppColors.textPrimary,
                  size: 15,
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
    );
  }
}