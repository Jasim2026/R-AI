import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
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
            // RAG chunk toolbar (shows last used chunks, persistent until next inference)
            if (!isBusy && chatProvider.lastRagChunkIds != null && chatProvider.lastRagChunkIds!.isNotEmpty)
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
                        'Last context: ${chatProvider.lastRagChunkIds}',
                        style: AppColors.font(
                          size: 10,
                          color: AppColors.accent.withOpacity(0.7),
                          weight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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
