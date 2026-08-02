import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../widgets/gradient_background.dart';
import '../utils/theme.dart';

class SessionManagerScreen extends StatefulWidget {
  const SessionManagerScreen({super.key});

  @override
  State<SessionManagerScreen> createState() => _SessionManagerScreenState();
}

class _SessionManagerScreenState extends State<SessionManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionProvider>().loadSessions();
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
          title: Text(
            'Sessions',
            style: AppColors.font(
              color: AppColors.textPrimary,
              size: 24,
              weight: FontWeight.w700,
            ),
          ),
        ),
        body: Consumer<SessionProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingSessions) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (provider.sessions.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_outlined, color: AppColors.textHint, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'No sessions yet',
                      style: AppColors.font(
                        color: AppColors.textPrimary,
                        size: 18,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start a conversation from the Chat tab',
                      style: AppColors.font(
                        color: AppColors.textHint,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.sessions.length,
              itemBuilder: (context, index) {
                final session = provider.sessions[index];
                final isActive = provider.currentSession?.id == session.id;
                return _buildSessionCard(session, isActive, provider);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSessionCard(
    dynamic session,
    bool isActive,
    SessionProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isActive ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
            color: isActive ? AppColors.primary : AppColors.textHint,
            size: 18,
          ),
        ),
        title: Text(
          session.title ?? 'Untitled',
          style: AppColors.font(
            color: isActive ? AppColors.primary : AppColors.textPrimary,
            size: 14,
            weight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${session.messageCount ?? 0} messages · ${_formatDate(session.updatedAt)}',
          style: AppColors.font(color: AppColors.textHint, size: 11),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: AppColors.textHint.withOpacity(0.6),
            size: 16,
          ),
          color: AppColors.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onSelected: (value) async {
            switch (value) {
              case 'open':
                await provider.openSession(session.id);
                if (context.mounted) Navigator.pop(context);
                break;
              case 'rename':
                _showRenameDialog(session);
                break;
              case 'delete':
                _showDeleteConfirm(session, provider);
                break;
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'open',
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('Open', style: AppColors.font(size: 13, color: AppColors.textPrimary)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text('Rename', style: AppColors.font(size: 13, color: AppColors.textPrimary)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text('Delete', style: AppColors.font(size: 13, color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(dynamic session) {
    final controller = TextEditingController(text: session.title ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Rename Session',
          style: AppColors.font(color: AppColors.textPrimary, weight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          style: AppColors.font(color: AppColors.textPrimary),
          autofocus: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await context.read<SessionProvider>().renameSession(
                  session.id,
                  newTitle,
                );
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Save', style: AppColors.font(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(dynamic session, SessionProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Session',
          style: AppColors.font(color: AppColors.textPrimary, weight: FontWeight.w600),
        ),
        content: Text(
          'Delete "${session.title ?? 'Untitled'}" and all its messages?',
          style: AppColors.font(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppColors.font(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteSession(session.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Delete', style: AppColors.font(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
