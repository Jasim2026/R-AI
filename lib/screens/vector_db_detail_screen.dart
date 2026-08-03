import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/vector_db.dart';
import '../models/vector_chunk.dart';
import '../providers/rag_provider.dart';
import '../services/cache_service.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';

class VectorDbDetailScreen extends StatefulWidget {
  final VectorDb db;

  const VectorDbDetailScreen({super.key, required this.db});

  @override
  State<VectorDbDetailScreen> createState() => _VectorDbDetailScreenState();
}

class _VectorDbDetailScreenState extends State<VectorDbDetailScreen> {
  List<VectorChunk> _chunks = [];
  bool _loading = true;
  bool _hasMore = true;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadChunks();
  }

  Future<void> _loadChunks() async {
    final provider = context.read<RagProvider>();
    final chunks = await provider.loadChunks(
      widget.db.filePath,
      limit: _pageSize,
      offset: _chunks.length,
    );

    setState(() {
      _chunks.addAll(chunks);
      _hasMore = chunks.length == _pageSize;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.db.displayName,
                style: AppColors.font(
                  color: AppColors.textPrimary,
                  size: 20,
                  weight: FontWeight.w600,
                ),
              ),
              Text(
                '${widget.db.chunkCount} chunks · ${widget.db.embeddingDimension}d',
                style: AppColors.font(
                  color: AppColors.textHint,
                  size: 12,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.add_rounded, size: 22),
              onPressed: () => _showAddTextDialog(),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _chunks.isEmpty
                ? _buildEmptyState()
                : _buildChunkList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, color: AppColors.textHint, size: 48),
          SizedBox(height: 16),
          Text(
            'No chunks in this database',
            style: AppColors.font(color: AppColors.textHint, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildChunkList() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _chunks.clear();
          _loading = true;
        });
        await _loadChunks();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _chunks.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _chunks.length) {
            return _loadMoreIndicator();
          }
          return _buildChunkCard(_chunks[index]);
        },
      ),
    );
  }

  Widget _loadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: TextButton(
          onPressed: () async {
            await _loadChunks();
          },
          child: Text('Load more'),
        ),
      ),
    );
  }

  Widget _buildChunkCard(VectorChunk chunk) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${chunk.id}',
                  style: AppColors.font(
                    color: AppColors.accent,
                    size: 10,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 16),
                color: AppColors.textHint,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showEditDialog(chunk),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16),
                color: AppColors.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _confirmDelete(chunk),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            chunk.text,
            style: AppColors.font(
              color: AppColors.textPrimary,
              size: 13,
              height: 1.5,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _showEditDialog(VectorChunk chunk) {
    final controller = TextEditingController(text: chunk.text);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Edit Chunk #${chunk.id}'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          style: AppColors.font(color: AppColors.textPrimary),
          decoration: const InputDecoration(
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
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isEmpty || newText == chunk.text) {
                Navigator.pop(context);
                return;
              }

              final provider = context.read<RagProvider>();
              await provider.editChunkText(widget.db.filePath, chunk.id, newText);

              setState(() {
                final idx = _chunks.indexWhere((c) => c.id == chunk.id);
                if (idx >= 0) {
                  _chunks[idx] = VectorChunk(
                    id: chunk.id,
                    text: newText,
                    vector: chunk.vector,
                    source: chunk.source,
                    createdAt: chunk.createdAt,
                  );
                }
              });

              if (mounted) Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(VectorChunk chunk) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete Chunk'),
        content: Text('Delete chunk #${chunk.id}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final provider = context.read<RagProvider>();
              await provider.deleteChunks(widget.db.filePath, [chunk.id]);

              setState(() {
                _chunks.removeWhere((c) => c.id == chunk.id);
              });

              if (mounted) Navigator.pop(context);
            },
            child: Text('Delete', style: AppColors.font(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _showAddTextDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Add Text'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: AppColors.font(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter text to process...',
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
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              // Read providers BEFORE popping dialog
              final provider = context.read<RagProvider>();
              final cacheService = context.read<CacheService>();

              Navigator.pop(context);

              await provider.processText(
                dbPath: widget.db.filePath,
                text: text,
                chunkSize: cacheService.chunkAutoSize
                    ? (text.length < 500 ? 200 : text.length < 2000 ? 300 : text.length < 10000 ? 500 : text.length < 50000 ? 700 : 1000)
                    : cacheService.chunkSize,
                chunkOverlap: cacheService.chunkOverlap,
                separator: cacheService.chunkSeparator.isEmpty ? null : cacheService.chunkSeparator,
                searchMode: cacheService.searchMode,
              );

              // Reload chunks
              if (mounted) {
                setState(() {
                  _chunks.clear();
                  _loading = true;
                });
                await _loadChunks();
              }
            },
            child: Text('Process'),
          ),
        ],
      ),
    );
  }
}
