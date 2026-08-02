import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/embedding_model_provider.dart';
import '../providers/rag_provider.dart';
import '../models/embedding_model.dart';
import '../models/vector_db.dart';
import '../services/cache_service.dart';
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
            _buildImportButton(context, provider),
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
          '${model.dimensions}d · ${model.path.split('/').last}',
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
                onPressed: () async {
                  await provider.loadModel(model);
                },
                child: Text('Load', style: AppColors.font(size: 12)),
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

  Widget _buildImportButton(BuildContext context, EmbeddingModelProvider provider) {
    return SizedBox(
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
                  await provider.importModel();
                },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Import Embedding Model',
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
            ],
          ],
        );
      },
    );
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
            final chunkSize = cacheService.chunkSize;
            final chunkOverlap = cacheService.chunkOverlap;

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

  void _showAddTextDialog(BuildContext context, RagProvider provider) {
    final textController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add Text'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
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
              ),
            ],
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

              Navigator.pop(context);

              // Create or get db
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

              // Process text
              final cacheService = context.read<CacheService>();
              await provider.processText(
                dbPath: dbPath,
                text: text,
                chunkSize: cacheService.chunkSize,
                chunkOverlap: cacheService.chunkOverlap,
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

  const _ProcessingDialog({
    required this.provider,
    required this.filePath,
    required this.dbName,
    required this.chunkSize,
    required this.chunkOverlap,
  });

  @override
  State<_ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<_ProcessingDialog> {
  int _current = 0;
  int _total = 0;
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

      // First, chunk to get total
      final chunker = TextChunker(
        chunkSize: widget.chunkSize,
        chunkOverlap: widget.chunkOverlap,
      );
      final chunks = chunker.chunk(text);
      _total = chunks.length;

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

      // Process with progress
      await widget.provider.processText(
        dbPath: dbPath,
        text: text,
        chunkSize: widget.chunkSize,
        chunkOverlap: widget.chunkOverlap,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _current = current;
              _total = total;
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
              'Processing chunks... $_current/$_total',
              style: AppColors.font(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _total > 0 ? _current / _total : 0,
              backgroundColor: AppColors.surfaceLight,
              color: AppColors.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _RagSettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer2<CacheService, RagProvider>(
      builder: (context, cache, rag, _) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('CHUNKING'),
            const SizedBox(height: 8),
            _buildSettingTile(
              icon: Icons.straighten,
              title: 'Chunk Size',
              subtitle: '${cache.chunkSize} characters',
              child: Slider(
                value: cache.chunkSize.toDouble(),
                min: 100,
                max: 2000,
                divisions: 19,
                onChanged: (v) => cache.chunkSize = v.round(),
              ),
            ),
            _buildSettingTile(
              icon: Icons.view_agenda_outlined,
              title: 'Chunk Overlap',
              subtitle: '${cache.chunkOverlap} characters',
              child: Slider(
                value: cache.chunkOverlap.toDouble(),
                min: 0,
                max: 200,
                divisions: 20,
                onChanged: (v) => cache.chunkOverlap = v.round(),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionHeader('RETRIEVAL'),
            const SizedBox(height: 8),
            _buildSettingTile(
              icon: Icons.format_list_numbered_rounded,
              title: 'Top-K Results',
              subtitle: '${cache.ragTopK} results',
              child: DropdownButton<int>(
                value: cache.ragTopK,
                dropdownColor: AppColors.surface,
                style: AppColors.font(color: AppColors.textPrimary),
                items: [3, 5, 10, 15, 20].map((k) {
                  return DropdownMenuItem(value: k, child: Text('$k'));
                }).toList(),
                onChanged: (v) {
                  if (v != null) cache.ragTopK = v;
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
              Text(
                subtitle,
                style: AppColors.font(
                  color: AppColors.textHint,
                  size: 12,
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
}

class TextChunker {
  final int chunkSize;
  final int chunkOverlap;

  const TextChunker({this.chunkSize = 500, this.chunkOverlap = 50});

  List<String> chunk(String text) {
    if (text.trim().isEmpty) return [];
    final clean = text.trim();
    if (clean.length <= chunkSize) return [clean];

    final chunks = <String>[];
    var start = 0;

    while (start < text.length) {
      var end = start + chunkSize;
      if (end < text.length) {
        final lastSpace = text.lastIndexOf(' ', end);
        final lastNewline = text.lastIndexOf('\n', end);
        final breakPoint = lastSpace > lastNewline ? lastSpace : lastNewline;
        if (breakPoint > start + chunkSize * 0.5) {
          end = breakPoint + 1;
        }
      } else {
        end = text.length;
      }

      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);

      start = end - chunkOverlap;
      if (start >= text.length) break;
    }

    return chunks;
  }
}
