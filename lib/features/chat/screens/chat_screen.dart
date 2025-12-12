import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import '../providers/chat_providers.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/session_selector.dart';
import '../widgets/agent_selector.dart';

/// Main chat screen for AI conversations
///
/// Supports:
/// - Streaming responses with real-time text and tool call display
/// - Session switching via bottom sheet
/// - Agent selection
/// - Initial context (e.g., from recording transcript)
/// - Auto-run mode for standalone agents
class ChatScreen extends ConsumerStatefulWidget {
  /// Optional initial message to pre-fill
  final String? initialMessage;

  /// Optional context to include with first message (e.g., recording transcript)
  final String? initialContext;

  /// If true, automatically sends [autoRunMessage] on screen load
  final bool autoRun;

  /// Message to auto-send when [autoRun] is true
  final String? autoRunMessage;

  const ChatScreen({
    super.key,
    this.initialMessage,
    this.initialContext,
    this.autoRun = false,
    this.autoRunMessage,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _pendingInitialContext;
  bool _hasAutoRun = false;

  @override
  void initState() {
    super.initState();
    _pendingInitialContext = widget.initialContext;

    // Schedule auto-run after first frame
    if (widget.autoRun && widget.autoRunMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performAutoRun();
      });
    }
  }

  void _performAutoRun() {
    if (_hasAutoRun) return;
    _hasAutoRun = true;
    _handleSend(widget.autoRunMessage!);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Motion.standard,
          curve: Motion.settling,
        );
      });
    }
  }

  void _handleSend(String message) {
    final selectedAgent = ref.read(selectedAgentProvider);

    ref.read(chatMessagesProvider.notifier).sendMessage(
          message: message,
          agentPath: selectedAgent?.path,
          initialContext: _pendingInitialContext,
        );

    // Clear pending context after first message
    _pendingInitialContext = null;

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatState = ref.watch(chatMessagesProvider);
    final currentSessionId = ref.watch(currentSessionIdProvider);

    // Auto-scroll when new messages arrive
    ref.listen(chatMessagesProvider, (previous, next) {
      if (next.messages.length != (previous?.messages.length ?? 0)) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        surfaceTintColor: Colors.transparent,
        title: _buildTitle(context, isDark, currentSessionId),
        actions: [
          // Agent selector
          const AgentSelector(),
          const SizedBox(width: Spacing.sm),
          // New chat button
          IconButton(
            onPressed: () => ref.read(newChatProvider)(),
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New Chat',
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: [
          // Context banner (if initial context provided)
          if (_pendingInitialContext != null)
            _buildContextBanner(context, isDark),

          // Messages list
          Expanded(
            child: chatState.messages.isEmpty
                ? _buildEmptyState(context, isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(
                        message: chatState.messages[index],
                      );
                    },
                  ),
          ),

          // Error banner
          if (chatState.error != null)
            _buildErrorBanner(context, isDark, chatState.error!),

          // Input field
          ChatInput(
            onSend: _handleSend,
            enabled: !chatState.isStreaming,
            initialText: widget.initialMessage,
            hintText: _pendingInitialContext != null
                ? 'Ask about this recording...'
                : 'Message your vault...',
          ),
        ],
      ),
    );
  }

  Widget _buildTitle(BuildContext context, bool isDark, String? sessionId) {
    final chatState = ref.watch(chatMessagesProvider);
    final sessionTitle = chatState.sessionTitle;

    // Determine title text
    String titleText;
    if (sessionId == null) {
      titleText = 'New Chat';
    } else if (sessionTitle != null && sessionTitle.isNotEmpty) {
      titleText = sessionTitle;
    } else {
      titleText = 'Chat';
    }

    return GestureDetector(
      onTap: () => SessionSelector.show(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 20,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          const SizedBox(width: Spacing.sm),
          Flexible(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.xl),
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.nightSurfaceElevated
                    : BrandColors.forestMist.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_outlined,
                size: 48,
                color: isDark ? BrandColors.nightForest : BrandColors.forest,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: TypographyTokens.headlineSmall,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Ask questions about your vault, get help with ideas,\nor explore your recordings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
                height: TypographyTokens.lineHeightRelaxed,
              ),
            ),
            const SizedBox(height: Spacing.xxl),
            // Quick action suggestions
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                  label: 'Summarize my recent notes',
                  onTap: () => _handleSend('Summarize my recent notes'),
                ),
                _SuggestionChip(
                  label: 'What did I talk about today?',
                  onTap: () => _handleSend('What did I talk about today?'),
                ),
                _SuggestionChip(
                  label: 'Find ideas about...',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextBanner(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.nightTurquoise.withValues(alpha: 0.1)
            : BrandColors.turquoiseMist,
        borderRadius: Radii.card,
        border: Border.all(
          color: isDark
              ? BrandColors.nightTurquoise.withValues(alpha: 0.3)
              : BrandColors.turquoiseLight,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 20,
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Recording context attached',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color:
                    isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _pendingInitialContext = null;
              });
            },
            icon: Icon(
              Icons.close,
              size: 18,
              color:
                  isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep,
            ),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, bool isDark, String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
      padding: const EdgeInsets.all(Spacing.sm),
      decoration: BoxDecoration(
        color: BrandColors.errorLight,
        borderRadius: Radii.badge,
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: BrandColors.error,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: BrandColors.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: isDark
          ? BrandColors.nightSurfaceElevated
          : BrandColors.stone.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        fontSize: TypographyTokens.labelMedium,
        color: isDark ? BrandColors.nightText : BrandColors.charcoal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: Radii.badge,
        side: BorderSide(
          color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.stone,
        ),
      ),
    );
  }
}
