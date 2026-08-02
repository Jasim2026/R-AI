import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../utils/theme.dart';
import 'markdown_message.dart';
import 'rag_context_chip.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isLast;

  const MessageBubble({
    super.key,
    required this.message,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final hasError = message.error != null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 12,
          right: isUser ? 12 : 48,
          top: 2,
          bottom: 2,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.psychology,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'R-AI',
                      style: AppColors.font(
                        size: 10,
                        weight: FontWeight.w600,
                        color: AppColors.textHint,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: hasError
                    ? AppColors.error.withOpacity(0.08)
                    : isUser
                        ? AppColors.userBubble
                        : AppColors.assistantBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: hasError
                    ? Border.all(
                        color: AppColors.error.withOpacity(0.3), width: 0.5)
                    : isUser
                        ? null
                        : Border.all(
                            color: AppColors.divider,
                            width: 0.5,
                          ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasError)
                    SelectableText(
                      message.content,
                      style: AppColors.font(
                        size: 13,
                        color: AppColors.error,
                        height: 1.5,
                      ),
                    )
                  else
                    MarkdownMessage(
                      content: message.content,
                      isUser: isUser,
                      isStreaming: message.isStreaming,
                    ),
                  if (isLast && message.isStreaming)
                    _buildStreamingIndicator(),
                  // Show RAG context chips below assistant messages
                  if (!isUser && message.ragContexts != null && message.ragContexts!.isNotEmpty)
                    RagContextChip(contexts: message.ragContexts!),
                ],
              ),
            ),
            const SizedBox(height: 2),
            _buildActionRow(context, isUser),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, bool isUser) {
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 0 : 2,
        right: isUser ? 2 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(message.timestamp),
            style: AppColors.font(size: 9, color: AppColors.textHint),
          ),
          const SizedBox(width: 4),
          _MiniAction(
            icon: Icons.copy_rounded,
            tooltip: 'Copy',
            onTap: () {
              Clipboard.setData(ClipboardData(text: message.content));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied', style: AppColors.font(size: 11)),
                  duration: const Duration(seconds: 1),
                  backgroundColor: AppColors.surfaceLight,
                ),
              );
            },
          ),
          if (isUser)
            _MiniAction(
              icon: Icons.edit_outlined,
              tooltip: 'Edit',
              onTap: () => _showEditDialog(context),
            ),
          if (!isUser && message.error == null)
            _MiniAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Regenerate',
              onTap: () => _regenerate(context),
            ),
          _MiniAction(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete',
            color: AppColors.error,
            onTap: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.primary.withOpacity(0.6),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Generating...',
            style: AppColors.font(size: 10, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: message.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Message',
            style: AppColors.font(size: 16, weight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          maxLines: 6,
          style: AppColors.font(size: 14),
          decoration: const InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('Cancel', style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty && newContent != message.content) {
                _updateMessageContent(context, newContent);
              }
              Navigator.pop(ctx);
            },
            child: Text('Save',
                style: AppColors.font(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _updateMessageContent(BuildContext context, String newContent) {
    final chatProvider = context.read<ChatProvider>();
    final session = chatProvider.currentSession;
    if (session == null) return;

    final idx = session.messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;

    session.messages[idx] =
        session.messages[idx].copyWith(content: newContent);
    chatProvider.notifyListeners();
  }

  void _regenerate(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final session = chatProvider.currentSession;
    if (session == null) return;

    final idx = session.messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return;

    session.messages.removeRange(idx, session.messages.length);

    final lastUserMsg = session.messages
        .where((m) => m.role == MessageRole.user)
        .lastOrNull;

    if (lastUserMsg != null) {
      chatProvider.sendMessage(lastUserMsg.content);
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Message',
            style: AppColors.font(size: 16, weight: FontWeight.w600)),
        content: Text(
          'Delete this message?',
          style: AppColors.font(size: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              _deleteMessage(context);
              Navigator.pop(ctx);
            },
            child: Text('Delete',
                style: AppColors.font(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _deleteMessage(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final session = chatProvider.currentSession;
    if (session == null) return;

    session.messages.removeWhere((m) => m.id == message.id);
    chatProvider.notifyListeners();
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${time.day}/${time.month}';
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Material(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: onTap,
              child: Icon(
                icon,
                size: 12,
                color: color ?? AppColors.textHint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
