import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/theme/design_tokens.dart';
import 'package:app/features/recorder/models/recording.dart';
import '../models/agent.dart';
import '../models/chat_session.dart';
import '../providers/chat_providers.dart';
import '../widgets/agent_card.dart';
import '../widgets/session_list_item.dart';
import '../widgets/document_picker.dart';
import 'chat_screen.dart';

/// Agent Hub - Main entry point for AI interactions
///
/// Displays available agents in a grid and recent sessions below.
/// All agent types (chatbot, standalone, doc) are accessible from here.
class AgentHubScreen extends ConsumerWidget {
  const AgentHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final agentsAsync = ref.watch(agentsProvider);
    final sessionsAsync = ref.watch(chatSessionsProvider);

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Agents',
          style: TextStyle(
            fontSize: TypographyTokens.titleLarge,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        actions: [
          // All sessions button
          IconButton(
            onPressed: () => _showAllSessions(context, ref),
            icon: Icon(
              Icons.history,
              color: isDark ? BrandColors.nightText : BrandColors.charcoal,
            ),
            tooltip: 'All Sessions',
          ),
          const SizedBox(width: Spacing.xs),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                // Agents grid
                agentsAsync.when(
                  data: (agents) => _buildAgentsGrid(context, ref, agents, isDark),
                  loading: () => _buildAgentsLoading(isDark),
                  error: (e, _) => _buildAgentsError(isDark, e.toString()),
                ),

                const SizedBox(height: Spacing.xl),

                // Recent sessions header
                _buildSectionHeader(
                  context,
                  isDark,
                  'Recent Sessions',
                  onSeeAll: () => _showAllSessions(context, ref),
                ),

                const SizedBox(height: Spacing.sm),

                // Recent sessions list
                sessionsAsync.when(
                  data: (sessions) => _buildRecentSessions(context, ref, sessions, isDark),
                  loading: () => _buildSessionsLoading(isDark),
                  error: (e, _) => _buildSessionsError(isDark, e.toString()),
                ),
              ],
            ),
          ),

          // Quick chat input at bottom
          _buildQuickChatInput(context, ref, isDark),
        ],
      ),
    );
  }

  Widget _buildAgentsGrid(
    BuildContext context,
    WidgetRef ref,
    List<Agent> agents,
    bool isDark,
  ) {
    // Always include vault agent at the start
    final allAgents = [vaultAgent, ...agents];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Spacing.md,
        crossAxisSpacing: Spacing.md,
        childAspectRatio: 1.3,
      ),
      itemCount: allAgents.length,
      itemBuilder: (context, index) {
        final agent = allAgents[index];
        return AgentCard(
          agent: agent,
          onTap: () => _handleAgentTap(context, ref, agent),
        );
      },
    );
  }

  Widget _buildAgentsLoading(bool isDark) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Spacing.md,
        crossAxisSpacing: Spacing.md,
        childAspectRatio: 1.3,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: isDark
                ? BrandColors.nightSurfaceElevated
                : BrandColors.softWhite,
            borderRadius: Radii.card,
          ),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAgentsError(bool isDark, String error) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.errorLight,
        borderRadius: Radii.card,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: BrandColors.error),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Failed to load agents: $error',
              style: TextStyle(color: BrandColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    bool isDark,
    String title, {
    VoidCallback? onSeeAll,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: TypographyTokens.titleSmall,
            fontWeight: FontWeight.w600,
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: Text(
              'See all',
              style: TextStyle(
                fontSize: TypographyTokens.labelMedium,
                color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecentSessions(
    BuildContext context,
    WidgetRef ref,
    List<ChatSession> sessions,
    bool isDark,
  ) {
    if (sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(Spacing.xl),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.nightSurfaceElevated
              : BrandColors.stone.withValues(alpha: 0.3),
          borderRadius: Radii.card,
        ),
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 32,
              color: isDark
                  ? BrandColors.nightTextSecondary
                  : BrandColors.driftwood,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'No conversations yet',
              style: TextStyle(
                color: isDark
                    ? BrandColors.nightTextSecondary
                    : BrandColors.driftwood,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Start by tapping an agent above',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                color: isDark
                    ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                    : BrandColors.driftwood.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    // Show only recent 5 sessions
    final recentSessions = sessions.take(5).toList();

    return Column(
      children: recentSessions.map((session) {
        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: SessionListItem(
            session: session,
            onTap: () => _handleSessionTap(context, ref, session),
            onDelete: () => _handleSessionDelete(ref, session),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSessionsLoading(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
        ),
      ),
    );
  }

  Widget _buildSessionsError(bool isDark, String error) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: BrandColors.errorLight,
        borderRadius: Radii.card,
      ),
      child: Text(
        'Failed to load sessions: $error',
        style: TextStyle(color: BrandColors.error),
      ),
    );
  }

  Widget _buildQuickChatInput(BuildContext context, WidgetRef ref, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: () => _startNewChat(context, ref, null),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.nightSurface
                  : BrandColors.stone.withValues(alpha: 0.5),
              borderRadius: Radii.pill,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 20,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Quick chat with Vault...',
                  style: TextStyle(
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleAgentTap(BuildContext context, WidgetRef ref, Agent agent) {
    if (agent.isStandalone) {
      _showStandaloneAgentDialog(context, ref, agent);
    } else if (agent.isDocAgent) {
      _showDocumentPicker(context, ref, agent);
    } else {
      // Chatbot - start new chat with this agent
      _startNewChat(context, ref, agent);
    }
  }

  void _startNewChat(BuildContext context, WidgetRef ref, Agent? agent) {
    // Clear current session and set agent
    ref.read(newChatProvider)();
    ref.read(selectedAgentProvider.notifier).state = agent;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ChatScreen(),
      ),
    );
  }

  void _handleSessionTap(BuildContext context, WidgetRef ref, ChatSession session) {
    // Load the session and navigate to chat
    ref.read(switchSessionProvider)(session.id);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ChatScreen(),
      ),
    );
  }

  Future<void> _handleSessionDelete(WidgetRef ref, ChatSession session) async {
    await ref.read(deleteSessionProvider)(session.id);
  }

  void _showAllSessions(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AllSessionsScreen(),
      ),
    );
  }

  void _showStandaloneAgentDialog(BuildContext context, WidgetRef ref, Agent agent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(agent.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 16, color: BrandColors.turquoise),
                const SizedBox(width: Spacing.xs),
                Text(
                  'Standalone Agent',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: BrandColors.turquoise,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            if (agent.description != null)
              Text(agent.description!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _runStandaloneAgent(context, ref, agent);
            },
            child: const Text('Run Agent'),
          ),
        ],
      ),
    );
  }

  void _runStandaloneAgent(BuildContext context, WidgetRef ref, Agent agent) {
    // For standalone agents, we start a new session and auto-send a trigger message
    ref.read(newChatProvider)();
    ref.read(selectedAgentProvider.notifier).state = agent;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          autoRun: true,
          autoRunMessage: 'Run', // Simple trigger for standalone agents
        ),
      ),
    );
  }

  void _showDocumentPicker(BuildContext context, WidgetRef ref, Agent agent) async {
    final recording = await DocumentPicker.show(
      context,
      agentName: agent.name,
    );

    if (recording != null && context.mounted) {
      _runDocAgentWithRecording(context, ref, agent, recording);
    }
  }

  void _runDocAgentWithRecording(
    BuildContext context,
    WidgetRef ref,
    Agent agent,
    Recording recording,
  ) async {
    // Show loading dialog while uploading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: Spacing.lg),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preparing document...'),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    recording.title,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: BrandColors.driftwood,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    try {
      // Upload the document to the server
      final chatService = ref.read(chatServiceProvider);

      // Build the markdown content to upload
      final content = _buildMarkdownContent(recording);
      final filename = '${recording.id}.md';

      await chatService.uploadDocument(
        filename: filename,
        content: content,
        title: recording.title,
        context: recording.context.isNotEmpty ? recording.context : null,
        timestamp: recording.timestamp,
      );

      // Close the loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Start the doc agent session with the document path
      if (context.mounted) {
        ref.read(newChatProvider)();
        ref.read(selectedAgentProvider.notifier).state = agent;

        // The message tells the agent which document to process
        final message = 'Process document: captures/$filename';

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              autoRun: true,
              autoRunMessage: message,
              initialContext: 'Document: ${recording.title}\n\n$content',
            ),
          ),
        );
      }
    } catch (e) {
      // Close the loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // Show error
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload document: $e'),
            backgroundColor: BrandColors.error,
          ),
        );
      }
    }
  }

  String _buildMarkdownContent(Recording recording) {
    final buffer = StringBuffer();

    // Title
    buffer.writeln('# ${recording.title}');
    buffer.writeln();

    // Metadata
    buffer.writeln(
      '**Date:** ${recording.timestamp.toLocal().toString().split('.')[0]}',
    );
    if (recording.context.isNotEmpty) {
      buffer.writeln('**Context:** ${recording.context}');
    }
    buffer.writeln();

    // Transcript
    buffer.writeln('## Transcript');
    buffer.writeln();
    buffer.writeln(recording.transcript);

    return buffer.toString();
  }
}

/// Screen showing all sessions
class AllSessionsScreen extends ConsumerWidget {
  const AllSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sessionsAsync = ref.watch(chatSessionsProvider);

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      appBar: AppBar(
        backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'All Sessions',
          style: TextStyle(
            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
          ),
        ),
      ),
      body: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    'No sessions yet',
                    style: TextStyle(
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.md),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return SessionListItem(
                session: session,
                onTap: () {
                  ref.read(switchSessionProvider)(session.id);
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const ChatScreen(),
                    ),
                  );
                },
                onDelete: () async {
                  await ref.read(deleteSessionProvider)(session.id);
                },
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(
            color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
          ),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: TextStyle(color: BrandColors.error),
          ),
        ),
      ),
    );
  }
}
