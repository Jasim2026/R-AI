import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/model_provider.dart';
import '../models/llm_model.dart';
import '../widgets/model_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';

class ModelImportScreen extends StatefulWidget {
  const ModelImportScreen({super.key});

  @override
  State<ModelImportScreen> createState() => _ModelImportScreenState();
}

class _ModelImportScreenState extends State<ModelImportScreen> {
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ModelProvider>().loadModels();
    });
  }

  Future<void> _importModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litertlm', 'tflite', 'bin', 'gguf', 'ggml', 'safetensors'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      setState(() => _isImporting = true);

      _showModelDetailsDialog(file.name, file.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    } finally {
      setState(() => _isImporting = false);
    }
  }

  void _showModelDetailsDialog(String fileName, String filePath) {
    final nameController = TextEditingController(
      text: fileName.replaceAll(RegExp(r'\.[^.]+$'), ''),
    );
    final descController = TextEditingController();
    BackendType backend = BackendType.gpu;
    int? paramSize;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.65,
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
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.8),
                              AppColors.accent.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.file_upload_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Import Model',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildInputField(
                        label: 'Model Name',
                        controller: nameController,
                        hint: 'Enter model name',
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        label: 'Description (optional)',
                        controller: descController,
                        hint: 'Brief description',
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'PREFERRED ACCELERATOR',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: BackendType.values.map((type) {
                          final isSelected = backend == type;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Material(
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.15)
                                    : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => setModalState(() {
                                    backend = type;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.divider,
                                        width: isSelected ? 1.5 : 0.5,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          type == BackendType.npu
                                              ? Icons.speed_rounded
                                              : type == BackendType.gpu
                                                  ? Icons.bolt_rounded
                                                  : Icons.memory_rounded,
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.textHint,
                                          size: 22,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          type.name.toUpperCase(),
                                          style: TextStyle(
                                            color: isSelected
                                                ? AppColors.primary
                                                : AppColors.textHint,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      _buildInfoRow(
                        Icons.storage_rounded,
                        'File',
                        fileName,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.sd_storage_rounded,
                        'Size',
                        _formatFileSize(File(filePath).lengthSync()),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _isImporting
                            ? null
                            : () async {
                                final model = LLMModel(
                                  name: nameController.text.trim(),
                                  path: filePath,
                                  description: descController.text.trim().isEmpty
                                      ? null
                                      : descController.text.trim(),
                                  backend: backend,
                                  parameterSize: paramSize,
                                );

                                await context.read<ModelProvider>().addModel(model);
                                if (mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${model.name} imported successfully'),
                                    ),
                                  );
                                }
                              },
                        child: Center(
                          child: _isImporting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Import Model',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textHint, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Models'),
          actions: [
            IconButton(
              onPressed: _isImporting ? null : _importModel,
              icon: const Icon(Icons.add_rounded, size: 24),
              tooltip: 'Import model',
            ),
          ],
        ),
        body: Consumer<ModelProvider>(
          builder: (context, modelProvider, _) {
            if (modelProvider.isLoading && modelProvider.models.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (modelProvider.models.isEmpty) {
              return EmptyState(
                icon: Icons.memory_rounded,
                title: 'No Models Yet',
                subtitle:
                    'Import a .litertlm model file from your device storage to get started.\n\nDownload models from HuggingFace LiteRT Community.',
                actionLabel: 'Import Model',
                onAction: _importModel,
              );
            }

            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lightbulb_outline,
                        color: AppColors.warning,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${modelProvider.models.length} model${modelProvider.models.length == 1 ? '' : 's'} imported. Tap a model to load it.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: modelProvider.models.length,
                    itemBuilder: (context, index) {
                      final model = modelProvider.models[index];
                      final isSelected =
                          modelProvider.selectedModel?.id == model.id;

                      return ModelCard(
                        model: model,
                        isSelected: isSelected,
                        onTap: () async {
                          if (isSelected) {
                            await modelProvider.unloadModel();
                          } else {
                            final success = await modelProvider.selectModel(model);
                            if (!success && mounted && modelProvider.error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(modelProvider.error!),
                                  backgroundColor: AppColors.error,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              modelProvider.clearError();
                            }
                          }
                        },
                        onDelete: () => _confirmDelete(
                          context,
                          modelProvider,
                          model,
                        ),
                        onSetDefault: () =>
                            modelProvider.setDefaultModel(model.id),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    ModelProvider modelProvider,
    LLMModel model,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Model'),
        content: Text(
          'Are you sure you want to remove "${model.name}"? This will delete the model file from storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              modelProvider.removeModel(model.id);
              Navigator.pop(context);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}