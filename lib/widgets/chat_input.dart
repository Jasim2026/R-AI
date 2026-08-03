import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/cache_service.dart';
import '../services/keyword_db_service.dart';
import '../services/keyword_search_engine.dart';
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

  // Live preview state
  Timer? _debounce;
  List<KeywordSearchResult> _liveResults = [];
  bool _liveSearching = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    // Debounced live search for threshold preview
    if (_showThresholdPanel) {
      _debounce?.cancel();
      if (_controller.text.trim().length >= 2) {
        _debounce = Timer(const Duration(milliseconds: 300), _runLiveSearch);
      } else {
        setState(() => _liveResults = []);
      }
    }
  }

  Future<void> _runLiveSearch() async {
    final query = _controller.text.trim();
    if (query.length < 2 || !_showThresholdPanel) return;

    setState(() => _liveSearching = true);
    try {
      final cacheService = context.read<CacheService>();
      final selectedDbs = cacheService.selectedRagDbList;
      final results = await KeywordDbService.searchAll(
        query: query,
        dbNames: selectedDbs.isEmpty ? null : selectedDbs,
      );
      if (mounted) {
        setState(() {
          _liveResults = results;
          _liveSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _liveSearching = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onInputChanged);
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
            // RAG chunk toolbar with threshold control
            if (!isBusy)
              chatProvider.lastRagChunkIds != null && chatProvider.lastRagChunkIds!.isNotEmpty
                  ? Container(
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
                          // Threshold toggle icon button
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _showThresholdPanel = !_showThresholdPanel;
                                if (_showThresholdPanel && _controller.text.trim().length >= 2) {
                                  _runLiveSearch();
                                }
                              });
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
                                _showThresholdPanel ? Icons.close : Icons.tune,
                                size: 14,
                                color: AppColors.accent.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            // Threshold seekbar panel — slides UP between toolbar and input
            if (_showThresholdPanel && !isBusy)
              _ThresholdPanel(
                liveResults: _liveResults,
                isSearching: _liveSearching,
                currentText: _controller.text,
                cacheService: context.read<CacheService>(),
                onThresholdChanged: () {
                  // Trigger rebuild to update filtered count
                  setState(() {});
                },
              ),
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
                        style: AppColors.font(size: 14, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: AppColors.font(
                            size: 14,
                            color: AppColors.textHint.withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  !isBusy ? _buildSendButton() : _buildStopButton(chatProvider),
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

/// Slide-up panel for adjusting keyword RAG similarity threshold (percentage).
/// Shows live preview of what would be retrieved for the current input text.
class _ThresholdPanel extends StatefulWidget {
  final List<KeywordSearchResult> liveResults;
  final bool isSearching;
  final String currentText;
  final CacheService cacheService;
  final VoidCallback onThresholdChanged;

  const _ThresholdPanel({
    required this.liveResults,
    required this.isSearching,
    required this.currentText,
    required this.cacheService,
    required this.onThresholdChanged,
  });

  @override
  State<_ThresholdPanel> createState() => _ThresholdPanelState();
}

class _ThresholdPanelState extends State<_ThresholdPanel> {
  late double _currentPct;

  static const double _min = 0.0;
  static const double _max = 100.0;

  @override
  void initState() {
    super.initState();
    _currentPct = widget.cacheService.ragMinScorePercent;
  }

  @override
  void didUpdateWidget(covariant _ThresholdPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync if externally changed
    if (oldWidget.cacheService.ragMinScorePercent != widget.cacheService.ragMinScorePercent) {
      _currentPct = widget.cacheService.ragMinScorePercent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.liveResults;
    final hasResults = results.isNotEmpty;
    final maxScore = hasResults ? results.first.score : 0.0;
    final threshold = maxScore * (_currentPct / 100.0);
    final passingCount = results.where((r) => r.score >= threshold).length;
    final totalCount = results.length;
    final passing = results.where((r) => r.score >= threshold).take(3).toList();

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.04),
          border: Border(
            bottom: BorderSide(
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
                      value: _currentPct,
                      min: _min,
                      max: _max,
                      divisions: 100,
                      onChanged: (v) {
                        setState(() => _currentPct = v);
                      },
                      onChangeEnd: (v) {
                        widget.cacheService.ragMinScorePercent = v;
                        HapticFeedback.selectionClick();
                        widget.onThresholdChanged();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${_currentPct.round()}%',
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
            // Live preview header
            if (widget.currentText.trim().length >= 2) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (widget.isSearching)
                    SizedBox(
                      width: 8,
                      height: 8,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.accent.withOpacity(0.5),
                      ),
                    )
                  else
                    Text(
                      hasResults
                          ? '$passingCount/$totalCount pass  •  max ${maxScore.toStringAsFixed(1)}'
                          : 'no matches',
                      style: AppColors.font(
                        size: 9,
                        color: AppColors.textSecondary.withOpacity(0.5),
                        weight: FontWeight.w500,
                      ),
                    ),
                  const Spacer(),
                  if (widget.cacheService.ragMinScoreOverridden)
                    GestureDetector(
                      onTap: () {
                        // Reset to dynamic default for current query
                        widget.cacheService.ragMinScorePercent =
                            CacheService.computeDefaultThresholdPercent(
                          widget.currentText,
                        );
                        setState(() => _currentPct = widget.cacheService.ragMinScorePercent);
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
              // Passing chunks preview
              if (passing.isNotEmpty) ...[
                const SizedBox(height: 3),
                ...passing.map((r) => Padding(
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
                              '${r.dbName}#${r.chunkId}  ${r.score.toStringAsFixed(1)}  ${r.text.length > 40 ? r.text.substring(0, 40) + '...' : r.text}',
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
          ],
        ),
      ),
    );
  }
}
