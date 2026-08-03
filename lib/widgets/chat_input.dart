import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/cache_service.dart';
import '../utils/theme.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({super.key});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _showThresholdPanel = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final chatProvider = context.read<ChatProvider>();
    final blockReason = chatProvider.checkInferencePrerequisites();

    if (blockReason != InferenceBlockReason.none) {
      _showBlockModal(chatProvider.getBlockReasonMessage(blockReason));
      return;
    }

    chatProvider.sendMessage(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _showBlockModal(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppColors.font(size: 14, height: 1.5, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: AppColors.font(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  String _statusIcon(GenerationStatus status) {
    switch (status) {
      case GenerationStatus.searchingDocuments:
        return 'Searching documents';
      case GenerationStatus.embeddingQuery:
        return 'Embedding your question';
      case GenerationStatus.foundContext:
        return 'Found relevant context';
      case GenerationStatus.buildingPrompt:
        return 'Building context prompt';
      case GenerationStatus.generatingResponse:
        return 'Thinking';
      case GenerationStatus.streamingTokens:
        return 'Writing';
      case GenerationStatus.idle:
        return '';
    }
  }

  IconData _statusIconData(GenerationStatus status) {
    switch (status) {
      case GenerationStatus.searchingDocuments:
        return Icons.search_rounded;
      case GenerationStatus.embeddingQuery:
        return Icons.psychology_rounded;
      case GenerationStatus.foundContext:
        return Icons.check_circle_outline_rounded;
      case GenerationStatus.buildingPrompt:
        return Icons.construction_rounded;
      case GenerationStatus.generatingResponse:
        return Icons.auto_awesome_rounded;
      case GenerationStatus.streamingTokens:
        return Icons.draw_rounded;
      case GenerationStatus.idle:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        final isBusy = chatProvider.isGenerating || chatProvider.isRagSearching;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Generation status bar
            if (isBusy)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    border: Border(
                      top: BorderSide(
                        color: AppColors.primary.withOpacity(0.15),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Animated icon
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _statusIconData(chatProvider.generationStatus),
                          key: ValueKey(chatProvider.generationStatus),
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Status text
                      Expanded(
                        child: Text(
                          _statusIcon(chatProvider.generationStatus),
                          style: AppColors.font(
                            size: 11,
                            color: AppColors.primary.withOpacity(0.8),
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // Token count during streaming
                      if (chatProvider.generationStatus == GenerationStatus.streamingTokens &&
                          chatProvider.tokenCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${chatProvider.tokenCount} tokens',
                            style: AppColors.font(
                              size: 9,
                              color: AppColors.primary,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // RAG chunk toolbar — shows last used context DBs and chunk IDs + threshold control
            if (!isBusy)
              chatProvider.lastRagChunkIds != null && chatProvider.lastRagChunkIds!.isNotEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.06),
                            border: Border(
                              top: BorderSide(
                                color: AppColors.accent.withOpacity(0.15),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.bookmark_outline,
                                size: 12,
                                color: AppColors.accent.withOpacity(0.7),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${chatProvider.lastRagDbNames ?? ""}  •  ${chatProvider.lastRagChunkIds}',
                                  style: AppColors.font(
                                    size: 10,
                                    color: AppColors.accent.withOpacity(0.7),
                                    weight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Threshold dropdown toggle button
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _showThresholdPanel = !_showThresholdPanel);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: _showThresholdPanel
                                        ? AppColors.accent.withOpacity(0.15)
                                        : AppColors.accent.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    _showThresholdPanel
                                        ? Icons.expand_less
                                        : Icons.tune,
                                    size: 14,
                                    color: AppColors.accent.withOpacity(0.8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Threshold seekbar panel (expands below)
                        if (_showThresholdPanel)
                          _ThresholdPanel(
                            chatProvider: chatProvider,
                            cacheService: context.read<CacheService>(),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            // Input area
            Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 8,
                top: 8,
                bottom: MediaQuery.of(context).padding.bottom + 8,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surfaceDark,
                border: Border(
                  top: BorderSide(
                    color: AppColors.divider,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _focusNode.hasFocus
                              ? AppColors.primary.withOpacity(0.4)
                              : AppColors.divider,
                          width: 0.5,
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        style: AppColors.font(size: 14),
                        decoration: InputDecoration(
                          hintText: 'Message R-AI...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          hintStyle: AppColors.font(
                            size: 14,
                            color: AppColors.textHint.withOpacity(0.5),
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  chatProvider.isGenerating
                      ? _buildStopButton(chatProvider)
                      : _buildSendButton(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: _hasText ? AppColors.primary : AppColors.surfaceLight,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _hasText ? _send : null,
          child: Icon(
            Icons.arrow_upward_rounded,
            color: _hasText ? Colors.white : AppColors.textHint,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildStopButton(ChatProvider provider) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Material(
        color: AppColors.error,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: provider.stopGeneration,
          child: const Icon(
            Icons.stop_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

// Inline seekbar panel for adjusting keyword RAG similarity threshold
class _ThresholdPanel extends StatefulWidget {
  final ChatProvider chatProvider;
  final CacheService cacheService;

  const _ThresholdPanel({
    required this.chatProvider,
    required this.cacheService,
  });

  @override
  State<_ThresholdPanel> createState() => _ThresholdPanelState();
}

class _ThresholdPanelState extends State<_ThresholdPanel> {
  late double _currentValue;
  late bool _isOverridden;

  // BM25 practical score range for seekbar
  static const double _min = 0.0;
  static const double _max = 30.0;

  @override
  void initState() {
    super.initState();
    _isOverridden = widget.cacheService.ragMinScoreOverridden;
    _currentValue = widget.cacheService.ragMinScore;
    _clamp();
  }

  void _clamp() {
    if (_currentValue < _min) _currentValue = _min;
    if (_currentValue > _max) _currentValue = _max;
  }

  @override
  Widget build(BuildContext context) {
    final contexts = widget.chatProvider.lastRagContexts;
    final passingCount = contexts.where((c) => c.score >= _currentValue).length;
    final totalCount = contexts.length;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.04),
          border: Border(
            top: BorderSide(
              color: AppColors.accent.withOpacity(0.1),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seekbar row
            Row(
              children: [
                Icon(
                  Icons.filter_alt_outlined,
                  size: 12,
                  color: AppColors.accent.withOpacity(0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  'min',
                  style: AppColors.font(
                    size: 9,
                    color: AppColors.textSecondary.withOpacity(0.6),
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: AppColors.accent.withOpacity(0.6),
                      inactiveTrackColor: AppColors.accent.withOpacity(0.15),
                      thumbColor: AppColors.accent,
                      overlayColor: AppColors.accent.withOpacity(0.1),
                    ),
                    child: Slider(
                      value: _currentValue,
                      min: _min,
                      max: _max,
                      divisions: 60,
                      onChanged: (v) {
                        setState(() => _currentValue = v);
                      },
                      onChangeEnd: (v) {
                        // Persist on release
                        widget.cacheService.ragMinScore = v;
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 30,
                  child: Text(
                    _currentValue.toStringAsFixed(1),
                    style: AppColors.font(
                      size: 10,
                      color: AppColors.accent,
                      weight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            // Passing chunks preview
            if (contexts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '$passingCount/$totalCount pass',
                    style: AppColors.font(
                      size: 9,
                      color: AppColors.textSecondary.withOpacity(0.5),
                      weight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (_isOverridden)
                    GestureDetector(
                      onTap: () {
                        // Reset to dynamic default
                        final query = widget.chatProvider.lastRagChunkIds ?? '';
                        widget.cacheService.ragMinScore = CacheService.computeDefaultMinScore(query);
                        setState(() {
                          _currentValue = widget.cacheService.ragMinScore;
                          _isOverridden = false;
                        });
                      },
                      child: Text(
                        'reset',
                        style: AppColors.font(
                          size: 9,
                          color: AppColors.accent.withOpacity(0.6),
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // Show up to 3 passing chunks
              ...contexts
                  .where((c) => c.score >= _currentValue)
                  .take(3)
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${c.dbName}#${c.chunkId}  ${c.score.toStringAsFixed(1)}  ${c.text.length > 40 ? c.text.substring(0, 40) + '...' : c.text}',
                                style: AppColors.font(
                                  size: 8,
                                  color: AppColors.textSecondary.withOpacity(0.6),
                                  weight: FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
            ],
          ],
        ),
      ),
    );
  }
}
