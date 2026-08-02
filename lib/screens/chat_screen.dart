import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/model_provider.dart';
import '../providers/session_provider.dart';
import '../services/ram_monitor_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_background.dart';
import '../widgets/ram_usage_indicator.dart';
import '../utils/theme.dart';
import '../screens/session_manager_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollDown = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (atBottom != _showScrollDown) {
      setState(() => _showScrollDown = !atBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      showOrbs: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(),
        drawer: _buildSessionDrawer(),
        body: Column(
          children: [
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, _) {
                  final messages =
                      chatProvider.currentSession?.messages ?? [];

                  if (messages.isEmpty) {
                    return _buildEmptyState(chatProvider);
                  }

                  return Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final isLast = index == messages.length - 1;
                          return MessageBubble(
                            message: messages[index],
                            isLast: isLast,
                          );
                        },
                      ),
                      if (_showScrollDown)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _buildScrollDownButton(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const ChatInput(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surfaceDark,
          border: Border(
            bottom: BorderSide(
              color: AppColors.divider,
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded, size: 22),
                  color: AppColors.textSecondary,
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              _buildModelStatus(),
              const Spacer(),
              _buildRamIndicator(),
              const SizedBox(width: 4),
              _buildAppBarActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelStatus() {
    return Consumer<ModelProvider>(
      builder: (context, modelProvider, _) {
        final model = modelProvider.selectedModel;
        final isLoaded = modelProvider.isModelLoaded;

        return Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLoaded
                      ? [AppColors.primary, AppColors.accent]
                      : [AppColors.surfaceLight, AppColors.surfaceLight],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isLoaded ? Icons.memory_rounded : Icons.memory_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  model?.name ?? 'No Model',
                  style: AppColors.font(
                    size: 14,
                    weight: FontWeight.w600,
                    color: isLoaded
                        ? AppColors.textPrimary
                        : AppColors.textHint,
                  ),
                ),
                Text(
                  isLoaded
                      ? '${model!.backendName} Accelerated'
                      : 'Tap to load a model',
                  style: AppColors.font(
                    size: 11,
                    color: isLoaded
                        ? AppColors.success
                        : AppColors.textHint.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRamIndicator() {
    final monitor = context.read<RamMonitorService>();
    return RamUsageIndicator(monitor: monitor);
  }

  Widget _buildAppBarActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: Icons.add_rounded,
          onTap: () {
            context.read<ChatProvider>().createNewSession();
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
      ),
    );
  }

  Widget _buildSessionDrawer() {
    return Drawer(
      backgroundColor: AppColors.surfaceDark,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Text(
                'Sessions',
                style: AppColors.font(
                  size: 22,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProvider, _) {
                  final sessions = chatProvider.sessions;

                  if (sessions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, color: AppColors.textHint, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            'No sessions yet',
                            style: AppColors.font(color: AppColors.textHint, size: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final isActive = chatProvider.currentSession?.id == session.id;

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          leading: Icon(
                            isActive
                                ? Icons.chat_bubble_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: isActive ? AppColors.primary : AppColors.textHint,
                          ),
                          title: Text(
                            session.title ?? 'Untitled',
                            style: AppColors.font(
                              size: 13,
                              weight: isActive ? FontWeight.w600 : FontWeight.w400,
                              color: isActive ? AppColors.primary : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${session.messages.length} msgs',
                            style: AppColors.font(size: 10, color: AppColors.textHint),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 14,
                              color: AppColors.textHint.withOpacity(0.6),
                            ),
                            color: AppColors.surfaceLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            onSelected: (value) async {
                              switch (value) {
                                case 'open':
                                  await chatProvider.selectSession(session.id);
                                  break;
                                case 'rename':
                                  _showRenameDialog(session);
                                  break;
                                case 'delete':
                                  await chatProvider.deleteSession(session.id);
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(value: 'open', child: Text('Open', style: AppColors.font(size: 12))),
                              PopupMenuItem(value: 'rename', child: Text('Rename', style: AppColors.font(size: 12))),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete', style: AppColors.font(size: 12, color: AppColors.error)),
                              ),
                            ],
                          ),
                          onTap: () async {
                            await chatProvider.selectSession(session.id);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SessionManagerScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.manage_search_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Manage Sessions',
                            style: AppColors.font(
                              size: 13,
                              weight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
          'Rename',
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
                await context.read<ChatProvider>().deleteSession(session.id);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Save', style: AppColors.font(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ChatProvider chatProvider) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.2),
                  AppColors.accent.withOpacity(0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(
              Icons.psychology_rounded,
              size: 48,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Hello there!',
            style: AppColors.font(
              size: 26,
              weight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'I\'m R-AI, your on-device AI assistant.\nLoad a model and start chatting.',
            style: AppColors.font(
              size: 15,
              color: AppColors.textHint,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildSuggestionChips(chatProvider),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips(ChatProvider chatProvider) {
    final suggestions = [
      'Hello, who are you?',
      'Explain quantum computing',
      'Write a quick dart function',
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions.map((suggestion) {
        return Material(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => chatProvider.sendMessage(suggestion),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.divider,
                  width: 0.5,
                ),
              ),
              child: Text(
                suggestion,
                style: AppColors.font(
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildScrollDownButton() {
    return Material(
      color: AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _scrollToBottom,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
