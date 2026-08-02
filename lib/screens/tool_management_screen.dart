import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/tool_definition.dart';
import '../providers/tool_provider.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';

class ToolManagementScreen extends StatefulWidget {
  const ToolManagementScreen({super.key});

  @override
  State<ToolManagementScreen> createState() => _ToolManagementScreenState();
}

class _ToolManagementScreenState extends State<ToolManagementScreen> {
  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Tool Calling',
            style: AppColors.font(
              color: AppColors.textPrimary,
              size: 24,
              weight: FontWeight.w700,
            ),
          ),
        ),
        body: Consumer<ToolProvider>(
          builder: (context, provider, _) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildEnableToggle(provider),
                const SizedBox(height: 16),
                _buildSectionHeader('DEFINED TOOLS'),
                const SizedBox(height: 8),
                if (provider.tools.isEmpty)
                  _buildEmptyState()
                else
                  ...provider.tools.map((tool) => _buildToolCard(provider, tool)),
                const SizedBox(height: 16),
                _buildAddToolButton(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEnableToggle(ToolProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: provider.toolCallingEnabled
            ? AppColors.success.withOpacity(0.1)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: provider.toolCallingEnabled
              ? AppColors.success.withOpacity(0.3)
              : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: provider.toolCallingEnabled
                  ? AppColors.success.withOpacity(0.2)
                  : AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.build_circle_rounded,
              color: provider.toolCallingEnabled
                  ? AppColors.success
                  : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tool Calling',
                  style: AppColors.font(
                    color: provider.toolCallingEnabled
                        ? AppColors.success
                        : AppColors.textPrimary,
                    size: 15,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Detect and execute tools from model responses',
                  style: AppColors.font(
                    color: AppColors.textHint,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: provider.toolCallingEnabled,
            onChanged: provider.setToolCallingEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppColors.font(
        color: AppColors.textHint,
        size: 11,
        weight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.build_circle_outlined, color: AppColors.textHint, size: 32),
          const SizedBox(height: 12),
          Text(
            'No tools defined yet',
            style: AppColors.font(color: AppColors.textHint, size: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Add tools to trigger actions from model responses',
            style: AppColors.font(color: AppColors.textHint, size: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard(ToolProvider provider, ToolDefinition tool) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: tool.enabled
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tool.enabled
              ? AppColors.primary.withOpacity(0.2)
              : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tool.executionType == ExecutionType.websocket
                ? AppColors.accent.withOpacity(0.1)
                : AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            tool.executionType == ExecutionType.websocket
                ? Icons.wifi_rounded
                : Icons.phone_android_rounded,
            color: tool.executionType == ExecutionType.websocket
                ? AppColors.accent
                : AppColors.warning,
            size: 18,
          ),
        ),
        title: Text(
          tool.name.isEmpty ? 'Unnamed Tool' : tool.name,
          style: AppColors.font(
            color: AppColors.textPrimary,
            size: 14,
            weight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${tool.detectionType.name}: ${tool.detectionPattern}',
          style: AppColors.font(color: AppColors.textHint, size: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: tool.enabled,
              onChanged: (_) => provider.toggleTool(tool.id),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppColors.textSecondary,
              onPressed: () => _showEditToolDialog(tool),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppColors.error,
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('Delete Tool'),
                    content: Text('Delete "${tool.name}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Delete', style: AppColors.font(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await provider.removeTool(tool.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddToolButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showAddToolDialog,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Add Tool',
                style: AppColors.font(
                  color: AppColors.primary,
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddToolDialog() {
    _showToolDialog();
  }

  void _showEditToolDialog(ToolDefinition tool) {
    _showToolDialog(tool: tool);
  }

  void _showToolDialog({ToolDefinition? tool}) {
    final isEdit = tool != null;
    final nameController = TextEditingController(text: tool?.name ?? '');
    final descController = TextEditingController(text: tool?.description ?? '');
    final promptController = TextEditingController(text: tool?.prompt ?? '');
    final patternController = TextEditingController(text: tool?.detectionPattern ?? '');
    final urlController = TextEditingController(text: tool?.websocketUrl ?? '');
    final triggerController = TextEditingController(text: tool?.websocketTrigger ?? '');
    final requestFormatController = TextEditingController(
      text: tool?.requestFormat ?? '{"action": "{trigger}", "data": "{content}"}',
    );
    final responseFormatController = TextEditingController(
      text: tool?.responseFormat ?? '{"result": "..."}',
    );

    DetectionType detectionType = tool?.detectionType ?? DetectionType.keyword;
    ExecutionType executionType = tool?.executionType ?? ExecutionType.websocket;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        isEdit ? 'Edit Tool' : 'New Tool',
                        style: AppColors.font(
                          color: AppColors.textPrimary,
                          size: 20,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildField('Name', nameController),
                      _buildField('Description', descController),
                      _buildField('Prompt / Instructions', promptController, maxLines: 3),
                      const SizedBox(height: 16),
                      _buildSectionLabel('DETECTION'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildTypeChip('Keyword', DetectionType.keyword, detectionType, (v) {
                            setModalState(() => detectionType = v);
                          }),
                          const SizedBox(width: 8),
                          _buildTypeChip('Regex', DetectionType.regex, detectionType, (v) {
                            setModalState(() => detectionType = v);
                          }),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildField('Detection Pattern', patternController),
                      const SizedBox(height: 16),
                      _buildSectionLabel('EXECUTION'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildTypeChip('WebSocket', ExecutionType.websocket, executionType, (v) {
                            setModalState(() => executionType = v);
                          }),
                          const SizedBox(width: 8),
                          _buildTypeChip('Native', ExecutionType.native, executionType, (v) {
                            setModalState(() => executionType = v);
                          }),
                        ],
                      ),
                      if (executionType == ExecutionType.websocket) ...[
                        const SizedBox(height: 8),
                        _buildField('WebSocket URL', urlController),
                        _buildField('Trigger', triggerController),
                        _buildField('Request Format', requestFormatController),
                        _buildField('Response Format', responseFormatController),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: Material(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final provider = context.read<ToolProvider>();
                              final newTool = ToolDefinition(
                                id: tool?.id,
                                name: nameController.text.trim(),
                                description: descController.text.trim(),
                                prompt: promptController.text.trim(),
                                detectionType: detectionType,
                                detectionPattern: patternController.text.trim(),
                                executionType: executionType,
                                websocketUrl: urlController.text.trim(),
                                websocketTrigger: triggerController.text.trim(),
                                requestFormat: requestFormatController.text.trim(),
                                responseFormat: responseFormatController.text.trim(),
                                enabled: tool?.enabled ?? true,
                              );

                              if (isEdit) {
                                await provider.updateTool(newTool);
                              } else {
                                await provider.addTool(newTool);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            child: Center(
                              child: Text(
                                isEdit ? 'Save' : 'Create',
                                style: AppColors.font(
                                  color: Colors.white,
                                  size: 15,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppColors.font(
              color: AppColors.textSecondary,
              size: 12,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: AppColors.font(color: AppColors.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: AppColors.font(
        color: AppColors.textHint,
        size: 11,
        weight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildTypeChip<T>(
    String label,
    T value,
    T current,
    ValueChanged<T> onChanged,
  ) {
    final isSelected = value == current;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
                : AppColors.divider,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppColors.font(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            size: 13,
            weight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
