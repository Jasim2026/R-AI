import 'package:flutter/material.dart';
import '../models/llm_model.dart';
import '../utils/theme.dart';

class ModelCard extends StatelessWidget {
  final LLMModel model;
  final bool isSelected;
  final bool isLoaded;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onSetDefault;

  const ModelCard({
    super.key,
    required this.model,
    this.isSelected = false,
    this.isLoaded = false,
    this.onTap,
    this.onDelete,
    this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.08)
                : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.divider,
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              _buildModelIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            model.name,
                            style: AppColors.font(
                              size: 14,
                              weight: FontWeight.w600,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (model.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'DEFAULT',
                              style: AppColors.font(
                                size: 8,
                                weight: FontWeight.w700,
                                color: AppColors.accent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildChip(model.parameterLabel, AppColors.primary),
                        const SizedBox(width: 4),
                        _buildChip(model.backendName, AppColors.accent),
                        if (model.hasMetadata) ...[
                          const SizedBox(width: 4),
                          _buildChip('Auto', AppColors.success),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    isLoaded ? Icons.power_settings_new : Icons.check_circle,
                    color: isLoaded ? AppColors.success : AppColors.primary,
                    size: 18,
                  ),
                ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: AppColors.textHint.withOpacity(0.6),
                  size: 16,
                ),
                color: AppColors.surfaceLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'default':
                      onSetDefault?.call();
                      break;
                    case 'delete':
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'default',
                    child: Row(
                      children: [
                        const Icon(Icons.star_outline, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('Set as Default', style: AppColors.font(size: 13, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                        const SizedBox(width: 8),
                        Text('Remove', style: AppColors.font(size: 13, color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.7),
            AppColors.accent.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.memory_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppColors.font(
          size: 9,
          weight: FontWeight.w600,
          color: color.withOpacity(0.8),
        ),
      ),
    );
  }
}
