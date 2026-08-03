import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/embedding_model_provider.dart';
import '../providers/rag_provider.dart';
import '../models/embedding_model.dart';
import '../models/vector_db.dart';
import '../services/cache_service.dart';
import '../services/vector_db_service.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';
import 'vector_db_detail_screen.dart';

class RagManagementScreen extends StatefulWidget {
  const RagManagementScreen({super.key});

  @override
  State<RagManagementScreen> createState() => _RagManagementScreenState();
}

class _RagManagementScreenState extends State<RagManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EmbeddingModelProvider>().loadModels();
      context.read<RagProvider>().loadDatabases();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'RAG Management',
            style: AppColors.font(
              color: AppColors.textPrimary,
              size: 24,
              weight: FontWeight.w700,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textHint,
            tabs: const [
              Tab(text: 'Embedder'),
              Tab(text: 'Documents'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _EmbedderTab(),
            _DocumentsTab(),
            _RagSettingsTab(),
          ],
        ),
      ),
    );
  }
}

class _EmbedderTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<EmbeddingModelProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(provider),
            const SizedBox(height: 16),
            _buildSectionHeader('IMPORTED MODELS'),
            const SizedBox(height: 8),
            if (provider.models.isEmpty)
              _buildEmptyState(
                icon: Icons.file_upload_outlined,
                message: 'No embedding models imported',
              )
            else
              ...provider.models.map((model) => _buildModelCard(context, provider, model)),
            const SizedBox(height: 16),
            _buildImportButtons(context, provider),
          ],
        );
      },
    );
  }

  Widget _buildStatusCard(EmbeddingModelProvider provider) {
    final isLoaded = provider.isLoaded;
    final isLoading = provider.isLoading;
    final selected = provider.selectedModel;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLoaded
            ? AppColors.success.withOpacity(0.1)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLoaded ? AppColors.success.withOpacity(0.3) : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isLoaded
                  ? AppColors.success.withOpacity(0.2)
                  : AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(
                    isLoaded ? Icons.check_circle_rounded : Icons.psychology_outlined,
                    color: isLoaded ? AppColors.success : AppColors.primary,
                    size: 20,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoaded ? 'Embedding Model Loaded' : 'No Model Loaded',
                  style: AppColors.font(
                    color: isLoaded ? AppColors.success : AppColors.textPrimary,
                    size: 15,
                    weight: FontWeight.w600,
                  ),
                ),
                if (selected != null)
                  Text(
                    '${selected.name} (${provider.embeddingDimension}d)',
                    style: AppColors.font(
                      color: AppColors.textHint,
                      size: 12,
                    ),
                  ),
              ],
            ),
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textHint, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppColors.font(
              color: AppColors.textHint,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, EmbeddingModelProvider provider, EmbeddingModel model) {
    final isSelected = provider.selectedModel?.id == model.id;
    final isLoaded = provider.isLoaded && isSelected;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primary.withOpacity(0.3) : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isLoaded
                ? AppColors.success.withOpacity(0.15)
                : AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isLoaded ? Icons.check_rounded : Icons.memory_rounded,
            color: isLoaded ? AppColors.success : AppColors.primary,
            size: 18,
          ),
        ),
        title: Text(
          model.name,
          style: AppColors.font(
            color: AppColors.textPrimary,
            size: 14,
            weight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${model.dimensions}d · ${model.vocabPath != null ? "has vocab.txt" : "no vocab.txt"} · ${model.path.split('/').last}',
          style: AppColors.font(
            color: AppColors.textHint,
            size: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLoaded)
              TextButton(
                onPressed: provider.isLoading
                    ? null
                    : () async {
                        // Show warning if no vocab
                        if (model.vocabPath == null) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'No vocab.txt found. Re-import with a zip containing '
                                  'both the .tflite model and vocab.txt.',
                                  style: AppColors.font(size: 12),
                                ),
                                backgroundColor: AppColors.warning,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                          return;
                        }
                        final success = await provider.loadModel(model);
                        if (context.mounted && !success) {
                          final error = provider.error ?? 'Failed to load embedding model';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(error, style: AppColors.font(size: 12)),
                              backgroundColor: AppColors.error,
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      },
                child: provider.isLoading && provider.selectedModel?.id == model.id
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : Text('Load', style: AppColors.font(size: 12)),
              ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18),
              color: AppColors.error,
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: Text('Remove Model'),
                    content: Text('Remove "${model.name}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Remove', style: AppColors.font(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await provider.removeModel(model.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButtons(BuildContext context, EmbeddingModelProvider provider) {
    return Column(
      children: [
        // Zip import button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Material(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: provider.isLoading
                  ? null
                  : () async {
                      final model = await provider.importZipModel();
                      if (context.mounted && model != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Imported: ${model.name}', style: AppColors.font(size: 12)),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Import Zip (model + vocab)',
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
        ),
        const SizedBox(height: 8),
        // Regular import button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Material(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: provider.isLoading
                  ? null
                  : () async {
                      final model = await provider.importModel();
                      if (context.mounted && model != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Imported: ${model.name}', style: AppColors.font(size: 12)),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.file_upload_outlined, color: AppColors.accent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Import Model (.tflite)',
                    style: AppColors.font(
                      color: AppColors.accent,
                      size: 14,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<RagProvider>(
      builder: (context, provider, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('DOCUMENTS'),
            const SizedBox(height: 8),
            if (!provider.embeddingProvider.isLoaded)
              _buildWarningCard(
                'Load an embedding model first from the Embedder tab',
              )
            else if (provider.dbs.isEmpty)
              _buildEmptyState(
                icon: Icons.description_outlined,
                message: 'No documents indexed',
              )
            else
              ...provider.dbs.map((db) => _buildDbCard(context, provider, db)),
            const SizedBox(height: 16),
            if (provider.embeddingProvider.isLoaded) ...[
              _buildImportDocumentButton(context, provider),
              const SizedBox(height: 8),
              _buildAddTextButton(context, provider),
              const SizedBox(height: 8),
              _buildImportDbButton(context, provider),
            ],
            if (provider.dbs.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildExportDbButton(context, provider),
            ],
          ],
        );
      },
    );
  }

  int _computeAutoChunkSize(int fileSizeBytes) {
    final sizeKb = fileSizeBytes / 1024;
    if (sizeKb < 10) return 200;
    if (sizeKb < 50) return 300;
    if (sizeKb < 200) return 500;
    if (sizeKb < 1000) return 700;
    return 1000;
  }

  Widget _buildWarningCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppColors.font(
                color: AppColors.warning,
                size: 13,
              ),
            ),
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textHint, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppColors.font(
              color: AppColors.textHint,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDbCard(BuildContext context, RagProvider provider, VectorDb db) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.storage_rounded,
            color: AppColors.accent,
            size: 18,
          ),
        ),
        title: Text(
          db.displayName,
          style: AppColors.font(
            color: AppColors.textPrimary,
            size: 14,
            weight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${db.chunkCount} chunks · ${db.embeddingDimension}d',
          style: AppColors.font(
            color: AppColors.textHint,
            size: 11,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_right, size: 20),
              color: AppColors.textHint,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VectorDbDetailScreen(db: db),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18),
              color: AppColors.error,
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: Text('Delete Database'),
                    content: Text('Delete "${db.displayName}" and all its chunks?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Delete', style: AppColors.font(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await provider.deleteDatabase(db.name);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportDocumentButton(BuildContext context, RagProvider provider) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['txt', 'md', 'json', 'csv'],
            );

            if (result == null || result.files.isEmpty) return;

            final file = result.files.first;
            if (file.path == null) return;

            final nameController = TextEditingController(
              text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
            );

            if (!context.mounted) return;

            final dbName = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text('Name Database'),
                content: TextField(
                  controller: nameController,
                  style: AppColors.font(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Enter database name',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, nameController.text.trim()),
                    child: Text('Process'),
                  ),
                ],
              ),
            );

            if (dbName == null || dbName.isEmpty) return;

            final cacheService = context.read<CacheService>();
            final chunkSize = cacheService.chunkAutoSize
                ? _computeAutoChunkSize(await File(file.path!).length())
                : cacheService.chunkSize;
            final chunkOverlap = cacheService.chunkOverlap;
            final separator = cacheService.chunkSeparator;

            // Show processing dialog
            if (!context.mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => _ProcessingDialog(
                provider: provider,
                filePath: file.path!,
                dbName: dbName,
                chunkSize: chunkSize,
                chunkOverlap: chunkOverlap,
                separator: separator,
              ),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.file_upload_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Import Document',
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

  Widget _buildAddTextButton(BuildContext context, RagProvider provider) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: AppColors.accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _showAddTextDialog(context, provider);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_note_rounded, color: AppColors.accent, size: 20),
              SizedBox(width: 8),
              Text(
                'Add Text Directly',
                style: AppColors.font(
                  color: AppColors.accent,
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

  Widget _buildImportDbButton(BuildContext context, RagProvider provider) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: AppColors.success.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['db'],
            );
            if (result == null || result.files.isEmpty) return;
            final file = result.files.first;
            if (file.path == null) return;

            final db = await VectorDbService.importDb(file.path!);
            if (context.mounted && db != null) {
              provider.loadDatabases();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Imported: ${db.name} (${db.chunkCount} chunks)', style: AppColors.font(size: 12)),
                  backgroundColor: AppColors.success,
                ),
              );
            } else if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to import database', style: AppColors.font(size: 12)),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.download_rounded, color: AppColors.success, size: 20),
              SizedBox(width: 8),
              Text(
                'Import Database (.db)',
                style: AppColors.font(
                  color: AppColors.success,
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

  Widget _buildExportDbButton(BuildContext context, RagProvider provider) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: provider.dbs.isEmpty ? null : () async {
            // Show picker for which DB to export
            final db = await showDialog<VectorDb>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppColors.surface,
                title: Text('Export Database'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: provider.dbs.length,
                    itemBuilder: (ctx, i) {
                      final db = provider.dbs[i];
                      return ListTile(
                        dense: true,
                        title: Text(db.displayName, style: AppColors.font(size: 14)),
                        subtitle: Text('${db.chunkCount} chunks', style: AppColors.font(size: 11, color: AppColors.textHint)),
                        onTap: () => Navigator.pop(ctx, db),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancel'),
                  ),
                ],
              ),
            );
            if (db == null || !context.mounted) return;

            final dest = await FilePicker.platform.saveFile(
              fileName: '${db.name}.db',
              type: FileType.custom,
              allowedExtensions: ['db'],
            );
            if (dest == null) return;

            final result = await VectorDbService.exportDb(db.name, dest);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result != null ? 'Exported to: $dest' : 'Export failed',
                    style: AppColors.font(size: 12),
                  ),
                  backgroundColor: result != null ? AppColors.success : AppColors.error,
                ),
              );
            }
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Export Database',
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

  void _showAddTextDialog(BuildContext context, RagProvider provider) {
    final textController = TextEditingController();
    final nameController = TextEditingController();
    final cache = context.read<CacheService>();
    final chunkSizeController = TextEditingController(text: cache.chunkSize.toString());
    bool autoChunkSize = cache.chunkAutoSize;
    String separator = cache.chunkSeparator;
    final separatorPresets = _RagSettingsTabState._separatorPresets;

    // Auto-detect chunk size based on text length
    int computeAutoChunkSize(int textLen) {
      if (textLen < 500) return 200;
      if (textLen < 2000) return 300;
      if (textLen < 10000) return 500;
      if (textLen < 50000) return 700;
      return 1000;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add Text'),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: AppColors.font(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Database name (or select existing)',
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    maxLines: 5,
                    style: AppColors.font(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Enter text to process...',
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                    ),
                    onChanged: (_) {
                      if (autoChunkSize) {
                        final auto = computeAutoChunkSize(textController.text.length);
                        chunkSizeController.text = auto.toString();
                      }
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  // Auto chunk size toggle
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('Auto chunk size', style: AppColors.font(size: 12, color: AppColors.textPrimary)),
                      const Spacer(),
                      Switch(
                        value: autoChunkSize,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          autoChunkSize = v;
                          if (v) {
                            final auto = computeAutoChunkSize(textController.text.length);
                            chunkSizeController.text = auto.toString();
                          }
                          setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                  if (!autoChunkSize) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: chunkSizeController,
                      keyboardType: TextInputType.number,
                      style: AppColors.font(color: AppColors.textPrimary, size: 13),
                      decoration: InputDecoration(
                        labelText: 'Chunk size (chars)',
                        labelStyle: AppColors.font(size: 11, color: AppColors.textHint),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Separator selector
                  Row(
                    children: [
                      Icon(Icons.vertical_split, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('Split by', style: AppColors.font(size: 12, color: AppColors.textPrimary)),
                      const Spacer(),
                      DropdownButton<String>(
                        value: separator,
                        isDense: true,
                        dropdownColor: AppColors.surface,
                        style: AppColors.font(color: AppColors.textPrimary, size: 12),
                        items: separatorPresets.where((p) => p['value'] != '__custom__').map((p) {
                          return DropdownMenuItem(
                            value: p['value'],
                            child: Text(p['label']!, style: AppColors.font(size: 11)),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            separator = v;
                            setDialogState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${textController.text.length} chars',
                      style: AppColors.font(size: 11, color: AppColors.textHint),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final text = textController.text.trim();
              final name = nameController.text.trim();
              if (text.isEmpty || name.isEmpty) return;

              final chunkSize = autoChunkSize
                  ? computeAutoChunkSize(text.length)
                  : (int.tryParse(chunkSizeController.text) ?? cache.chunkSize);

              Navigator.pop(context);

              String dbPath;
              final existing = provider.dbs.where(
                (d) => d.displayName == name,
              );

              if (existing.isNotEmpty) {
                dbPath = existing.first.filePath;
              } else {
                final db = await provider.createDatabase(name);
                dbPath = db.filePath;
              }

              await provider.processText(
                dbPath: dbPath,
                text: text,
                chunkSize: chunkSize,
                chunkOverlap: cache.chunkOverlap,
                separator: separator.isEmpty ? null : separator,
              );
            },
            child: Text('Process'),
          ),
        ],
      ),
    );
  }
}

class _ProcessingDialog extends StatefulWidget {
  final RagProvider provider;
  final String filePath;
  final String dbName;
  final int chunkSize;
  final int chunkOverlap;
  final String separator;

  const _ProcessingDialog({
    required this.provider,
    required this.filePath,
    required this.dbName,
    required this.chunkSize,
    required this.chunkOverlap,
    this.separator = '',
  });

  @override
  State<_ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<_ProcessingDialog> {
  int _current = 0;
  int _total = 0;
  String _currentChunk = '';
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _process();
  }

  Future<void> _process() async {
    try {
      final file = File(widget.filePath);
      final text = await file.readAsString();

      // Create db
      String dbPath;
      final existing = widget.provider.dbs.where(
        (d) => d.displayName == widget.dbName,
      );

      if (existing.isNotEmpty) {
        dbPath = existing.first.filePath;
      } else {
        final db = await widget.provider.createDatabase(widget.dbName);
        dbPath = db.filePath;
      }

      // Process with progress — one chunk at a time
      await widget.provider.processText(
        dbPath: dbPath,
        text: text,
        chunkSize: widget.chunkSize,
        chunkOverlap: widget.chunkOverlap,
        separator: widget.separator.isEmpty ? null : widget.separator,
        onProgress: (current, total, chunkPreview) {
          if (mounted) {
            setState(() {
              _current = current;
              _total = total;
              _currentChunk = chunkPreview;
            });
          }
        },
      );

      if (mounted) {
        setState(() => _done = true);
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error: $_error',
              style: AppColors.font(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ] else if (_done) ...[
            Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: 16),
            Text(
              'Done!',
              style: AppColors.font(
                color: AppColors.success,
                size: 16,
                weight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Processing chunk $_current/$_total',
              style: AppColors.font(
                color: AppColors.textPrimary,
                size: 14,
                weight: FontWeight.w600,
              ),
            ),
            if (_currentChunk.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currentChunk,
                  style: AppColors.font(
                    size: 11,
                    color: AppColors.textHint,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _total > 0 ? _current / _total : 0,
              backgroundColor: AppColors.surfaceLight,
              color: AppColors.primary,
            ),
            const SizedBox(height: 4),
            Text(
              '${(_total > 0 ? (_current / _total * 100) : 0).toStringAsFixed(0)}%',
              style: AppColors.font(
                size: 11,
                color: AppColors.textHint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RagSettingsTab extends StatefulWidget {
  @override
  State<_RagSettingsTab> createState() => _RagSettingsTabState();
}

class _RagSettingsTabState extends State<_RagSettingsTab> {
  String _ragMode = 'pre_generation';
  int _chunkSize = 500;
  int _chunkOverlap = 50;
  int _ragTopK = 5;
  bool _chunkAutoSize = true;
  String _chunkSeparator = '';
  bool _loaded = false;

  void _loadSettings(CacheService cache) {
    if (!_loaded) {
      _ragMode = cache.ragMode;
      _chunkSize = cache.chunkSize;
      _chunkOverlap = cache.chunkOverlap;
      _ragTopK = cache.ragTopK;
      _chunkAutoSize = cache.chunkAutoSize;
      _chunkSeparator = cache.chunkSeparator;
      _loaded = true;
    }
  }

  static const _separatorPresets = [
    {'label': 'Auto (word boundary)', 'value': ''},
    {'label': 'New line (\\n)', 'value': '\n'},
    {'label': 'Period (.)', 'value': '.'},
    {'label': 'Comma (,)', 'value': ','},
    {'label': 'Semicolon (;)', 'value': ';'},
    {'label': 'Colon (:)', 'value': ':'},
    {'label': 'Pipe (|)', 'value': '|'},
    {'label': 'Custom', 'value': '__custom__'},
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<RagProvider>(
      builder: (context, rag, _) {
        final cache = context.read<CacheService>();
        _loadSettings(cache);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('RAG MODE'),
            const SizedBox(height: 8),
            _buildSettingTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Mode',
              subtitle: _ragMode == 'pre_generation'
                  ? 'Pre-generation'
                  : 'Post-generation',
              child: DropdownButton<String>(
                value: _ragMode,
                dropdownColor: AppColors.surface,
                style: AppColors.font(color: AppColors.textPrimary),
                items: const [
                  DropdownMenuItem(
                    value: 'pre_generation',
                    child: Text('Pre-generation'),
                  ),
                  DropdownMenuItem(
                    value: 'post_generation',
                    child: Text('Post-generation'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _ragMode = v);
                    cache.ragMode = v;
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('CHUNKING'),
            const SizedBox(height: 8),
            _buildSettingTile(
              icon: Icons.auto_awesome,
              title: 'Auto Chunk Size',
              subtitle: _chunkAutoSize ? 'Suggested by text length' : 'Manual: $_chunkSize chars',
              child: Switch(
                value: _chunkAutoSize,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setState(() => _chunkAutoSize = v);
                  cache.chunkAutoSize = v;
                },
              ),
            ),
            if (!_chunkAutoSize) ...[
              const SizedBox(height: 4),
              _buildSettingTile(
                icon: Icons.straighten,
                title: 'Chunk Size',
                subtitle: '$_chunkSize characters',
                child: Slider(
                  value: _chunkSize.toDouble(),
                  min: 100,
                  max: 2000,
                  divisions: 19,
                  onChanged: (v) {
                    setState(() => _chunkSize = v.round());
                    cache.chunkSize = v.round();
                  },
                ),
              ),
            ],
            _buildSettingTile(
              icon: Icons.view_agenda_outlined,
              title: 'Chunk Overlap',
              subtitle: '$_chunkOverlap characters',
              child: Slider(
                value: _chunkOverlap.toDouble(),
                min: 0,
                max: 200,
                divisions: 20,
                onChanged: (v) {
                  setState(() => _chunkOverlap = v.round());
                  cache.chunkOverlap = v.round();
                },
              ),
            ),
            const SizedBox(height: 4),
            _buildSettingTile(
              icon: Icons.vertical_split,
              title: 'Split Separator',
              subtitle: _chunkSeparator.isEmpty
                  ? 'Auto (word boundary)'
                  : _chunkSeparator == '\n'
                      ? 'New line'
                      : '"${_chunkSeparator.replaceAll('\n', '\\n')}"',
              child: DropdownButton<String>(
                value: _chunkSeparator == '__custom__' ? '__custom__' : _chunkSeparator,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                style: AppColors.font(color: AppColors.textPrimary, size: 13),
                items: _separatorPresets.map((p) {
                  return DropdownMenuItem(
                    value: p['value'],
                    child: Text(p['label']!, style: AppColors.font(size: 12)),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  if (v == '__custom__') {
                    _showCustomSeparatorDialog(cache);
                  } else {
                    setState(() => _chunkSeparator = v);
                    cache.chunkSeparator = v;
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('RETRIEVAL'),
            const SizedBox(height: 8),
            _buildSettingTile(
              icon: Icons.format_list_numbered_rounded,
              title: 'Top-K Results',
              subtitle: '$_ragTopK results',
              child: DropdownButton<int>(
                value: _ragTopK,
                dropdownColor: AppColors.surface,
                style: AppColors.font(color: AppColors.textPrimary),
                items: [3, 5, 10, 15, 20].map((k) {
                  return DropdownMenuItem(value: k, child: Text('$k'));
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _ragTopK = v);
                    cache.ragTopK = v;
                  }
                },
              ),
            ),
          ],
        );
      },
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

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 12),
              Text(
                title,
                style: AppColors.font(
                  color: AppColors.textPrimary,
                  size: 14,
                  weight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  subtitle,
                  style: AppColors.font(
                    color: AppColors.textHint,
                    size: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  void _showCustomSeparatorDialog(CacheService cache) {
    final controller = TextEditingController(text: _chunkSeparator);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Custom Separator'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a custom text separator. Use \\n for newlines.',
              style: AppColors.font(size: 12, color: AppColors.textHint),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: AppColors.font(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'e.g. \\n--- , | , ===',
                filled: true,
                fillColor: AppColors.surfaceLight,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Reset dropdown to current value
              setState(() {});
            },
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final raw = controller.text;
              final value = raw.replaceAll('\\n', '\n');
              setState(() {
                _chunkSeparator = value;
                cache.chunkSeparator = value;
              });
              Navigator.pop(ctx);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}
