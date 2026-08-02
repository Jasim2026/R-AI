import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/model_provider.dart';
import '../models/llm_model.dart';
import '../services/litert_service.dart';
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

      ModelMetadata? metadata;
      if (file.name.endsWith('.litertlm')) {
        try {
          final service = LiteRTService();
          await service.initialize();
          metadata = await service.readModelMetadata(file.path!);
          service.dispose();
        } catch (e) {
          debugPrint('Failed to read model metadata: $e');
        }
      }

      _showModelDetailsDialog(file.name, file.path!, metadata);
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

  void _showModelDetailsDialog(String fileName, String filePath, ModelMetadata? metadata) {
    final nameController = TextEditingController(
      text: fileName.replaceAll(RegExp(r'\.[^.]+$'), ''),
    );
    final descController = TextEditingController();
    BackendType backend = metadata?.supportedBackends.isNotEmpty == true
        ? metadata!.supportedBackends.first
        : BackendType.gpu;
    int? paramSize;
    final supportedBackends = metadata?.supportedBackends ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.72,
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
                      if (supportedBackends.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'DETECTED ACCELERATORS',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'AUTO',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: supportedBackends.map((type) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.accent.withOpacity(0.3),
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    type == BackendType.npu
                                        ? Icons.speed_rounded
                                        : type == BackendType.gpu
                                            ? Icons.bolt_rounded
                                            : Icons.memory_rounded,
                                    color: AppColors.accent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    type.name.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],
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
                          final isSupported = supportedBackends.contains(type);
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
                                        if (isSupported) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: const BoxDecoration(
                                              color: AppColors.success,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
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
                      if (metadata?.detectedParams != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.info_outline_rounded,
                          'Info',
                          metadata!.detectedParams!,
                        ),
                      ],
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
                                  supportedBackends: supportedBackends,
                                  detectedParams: metadata?.detectedParams,
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
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Models',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Material(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _isImporting ? null : _importModel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _isImporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : const Icon(
                                Icons.add_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                        const SizedBox(width: 6),
                        Text(
                          _isImporting ? 'Importing...' : 'Import',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Consumer<ModelProvider>(
          builder: (context, modelProvider, child) {
            if (modelProvider.models.isEmpty) {
              return EmptyState(
                icon: Icons.phone_android_rounded,
                title: 'No models yet',
                subtitle: 'Import a .litertlm model file to get started',
                actionLabel: 'Import Model',
                onAction: _importModel,
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: modelProvider.models.length,
              itemBuilder: (context, index) {
                final model = modelProvider.models[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ModelCard(
                    model: model,
                    isSelected: model.id == modelProvider.selectedModel?.id,
                    onTap: () => modelProvider.selectModel(model),
                    onDelete: () => modelProvider.removeModel(model.id),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}