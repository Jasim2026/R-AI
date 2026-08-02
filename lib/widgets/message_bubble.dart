import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../utils/theme.dart';
import 'markdown_message.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isLast;

  const MessageBubble({
    super.key,
    required this.message,
    this.isLast = false,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showActions = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final hasError = widget.message.error != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _showActions = true),
      onExit: (_) => setState(() => _showActions = false),
      child: GestureDetector(
        onLongPress: () => setState(() => _showActions = !_showActions),
        child: AnimatedOpacity(
          opacity: 1.0,
          duration: const Duration(milliseconds: 200),
          child: Align(
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
                            widget.message.content,
                            style: AppColors.font(
                              size: 13,
                              color: AppColors.error,
                              height: 1.5,
                            ),
                          )
                        else
                          MarkdownMessage(
                            content: widget.message.content,
                            isUser: isUser,
                            isStreaming: widget.message.isStreaming,
                          ),
                        if (widget.isLast && widget.message.isStreaming)
                          _buildStreamingIndicator(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: _showActions
                        ? _buildActionButtons(isUser)
                        : _buildTimestamp(isUser),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimestamp(bool isUser) {
    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 0 : 2,
        right: isUser ? 2 : 0,
      ),
      child: Text(
        _formatTime(widget.message.timestamp),
        style: AppColors.font(size: 9, color: AppColors.textHint),
      ),
    );
  }

  Widget _buildActionButtons(bool isUser) {
    final actions = <_ActionDef>[];

    // Copy — always available
    actions.add(_ActionDef(
      icon: Icons.copy_rounded,
      onTap: () {
        Clipboard.setData(ClipboardData(text: widget.message.content));
        _showSnack('Copied to clipboard');
      },
    ));

    // Edit — user messages only
    if (isUser) {
      actions.add(_ActionDef(
        icon: Icons.edit_outlined,
        onTap: () => _showEditDialog(),
      ));
    }

    // Re-generate — assistant messages only, not errors
    if (!isUser && widget.message.error == null) {
      actions.add(_ActionDef(
        icon: Icons.refresh_rounded,
        onTap: () => _regenerate(),
      ));
    }

    // Delete — always available
    actions.add(_ActionDef(
      icon: Icons.delete_outline_rounded,
      color: AppColors.error,
      onTap: () => _confirmDelete(),
    ));

    return Padding(
      padding: EdgeInsets.only(
        left: isUser ? 0 : 2,
        right: isUser ? 2 : 0,
        top: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(widget.message.timestamp),
            style: AppColors.font(size: 9, color: AppColors.textHint),
          ),
          const SizedBox(width: 4),
          ...actions.map((a) => _buildActionButton(a)),
        ],
      ),
    );
  }

  Widget _buildActionButton(_ActionDef action) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SizedBox(
        width: 26,
        height: 26,
        child: Material(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: action.onTap,
            child: Icon(
              action.icon,
              size: 13,
              color: action.color ?? AppColors.textHint,
            ),
          ),
        ),
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

  void _showEditDialog() {
    final controller = TextEditingController(text: widget.message.content);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Message', style: AppColors.font(size: 16, weight: FontWeight.w600)),
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
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty && newContent != widget.message.content) {
                _updateMessageContent(newContent);
              }
              Navigator.pop(context);
            },
            child: Text('Save', style: AppColors.font(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _updateMessageContent(String newContent) {
    // Find the message in the session and update it
    final chatProvider = context.read<ChatProvider>();
    final session = chatProvider.currentSession;
    if (session == null) return;

    final idx = session.messages.indexWhere((m) => m.id == widget.message.id);
    if (idx < 0) return;

    session.messages[idx] = session.messages[idx].copyWith(content: newContent);
    chatProvider.notifyListeners();
  }

  void _regenerate() {
    final chatProvider = context.read<ChatProvider>();
    final session = chatProvider.currentSession;
    if (session == null) return;

    // Remove this message and all subsequent assistant messages
    final idx = session.messages.indexWhere((m) => m.id == widget.message.id);
    if (idx < 0) return;

    session.messages.removeRange(idx, session.messages.length);

    // Re-send the last user message
    final lastUserMsg = session.messages
        .where((m) => m.role == MessageRole.user)
        .lastOrNull;

    if (lastUserMsg != null) {
      chatProvider.sendMessage(lastUserMsg.content);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Message', style: AppColors.font(size: 16, weight: FontWeight.w600)),
        content: Text(
          'Are you sure you want to delete this message?',
          style: AppColors.font(size: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              _deleteMessage();
              Navigator.pop(context);
            },
            child: Text('Delete', style: AppColors.font(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _deleteMessage() {
    final chatProvider = context.read<ChatProvider>();
    final session = chatProvider.currentSession;
    if (session == null) return;

    session.messages.removeWhere((m) => m.id == widget.message.id);
    chatProvider.notifyListeners();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppColors.font(size: 12)),
        duration: const Duration(seconds: 1),
      ),
    );
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

class _ActionDef {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _ActionDef({required this.icon, this.color, required this.onTap});
}
