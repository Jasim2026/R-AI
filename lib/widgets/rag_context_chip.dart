import 'package:flutter/material.dart';
import '../models/message.dart';
import '../utils/theme.dart';

class RagContextChip extends StatefulWidget {
  final List<RagContext> contexts;

  const RagContextChip({super.key, required this.contexts});

  @override
  State<RagContextChip> createState() => _RagContextChipState();
}

class _RagContextChipState extends State<RagContextChip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.contexts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header chip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 12,
                      color: AppColors.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.contexts.length} source${widget.contexts.length > 1 ? 's' : ''}',
                      style: AppColors.font(
                        size: 10,
                        color: AppColors.primary.withOpacity(0.7),
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Show DB names as mini chips
                    ...widget.contexts
                        .map((c) => c.dbName)
                        .toSet()
                        .map((dbName) => Container(
                              margin: const EdgeInsets.only(left: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                dbName,
                                style: AppColors.font(
                                  size: 8,
                                  color: AppColors.accent,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            )),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        size: 14,
                        color: AppColors.primary.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Expanded details
              if (_expanded)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    itemCount: widget.contexts.length,
                    itemBuilder: (context, index) {
                      final ctx = widget.contexts[index];
                      final preview = ctx.text.length > 120
                          ? '${ctx.text.substring(0, 120)}...'
                          : ctx.text;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _scoreColor(ctx.score).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '${(ctx.score * 100).toStringAsFixed(0)}%',
                                    style: AppColors.font(
                                      size: 8,
                                      color: _scoreColor(ctx.score),
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Chunk #${ctx.chunkId}',
                                  style: AppColors.font(
                                    size: 9,
                                    color: AppColors.textHint,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              preview,
                              style: AppColors.font(
                                size: 10,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 0.8) return AppColors.success;
    if (score >= 0.6) return AppColors.primary;
    if (score >= 0.4) return AppColors.warning;
    return AppColors.error;
  }
}
