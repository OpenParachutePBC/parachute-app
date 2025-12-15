import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/design_tokens.dart';
import '../models/journal_day.dart';
import '../models/journal_entry.dart';
import '../providers/journal_providers.dart';
import '../widgets/journal_entry_card.dart';
import '../widgets/journal_input_bar.dart';

/// Main journal screen showing today's journal entries
///
/// The daily journal is the home for captures - voice notes, typed thoughts,
/// and links to longer recordings.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshJournal() async {
    ref.invalidate(todayJournalProvider);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final journalAsync = ref.watch(todayJournalProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? BrandColors.nightSurface : BrandColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, journalAsync),

            // Journal entries
            Expanded(
              child: journalAsync.when(
                data: (journal) => _buildJournalContent(context, journal),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => _buildErrorState(context, error),
              ),
            ),

            // Input bar at bottom
            JournalInputBar(
              onTextSubmitted: (text) async {
                final service = await ref.read(journalServiceFutureProvider.future);
                await service.addTextEntry(content: text);
                ref.invalidate(todayJournalProvider);
                _scrollToBottom();
              },
              onVoiceRecorded: (transcript, audioPath, duration) async {
                final service = await ref.read(journalServiceFutureProvider.future);
                await service.addVoiceEntry(
                  transcript: transcript,
                  audioPath: audioPath,
                  durationSeconds: duration,
                );
                ref.invalidate(todayJournalProvider);
                _scrollToBottom();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AsyncValue<JournalDay> journalAsync) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displayDate = journalAsync.when(
      data: (j) => j.displayDate,
      loading: () => 'Loading...',
      error: (_, _) => 'Today',
    );

    final isToday = journalAsync.when(
      data: (j) => j.isToday,
      loading: () => true,
      error: (_, _) => true,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        border: Border(
          bottom: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Date navigation (left arrow)
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              color: isDark ? BrandColors.driftwood : BrandColors.charcoal,
            ),
            onPressed: () {
              final currentDate = ref.read(selectedJournalDateProvider);
              ref.read(selectedJournalDateProvider.notifier).state =
                  currentDate.subtract(const Duration(days: 1));
            },
          ),

          Expanded(
            child: Column(
              children: [
                Text(
                  isToday ? 'Today' : '',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: BrandColors.forest,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  displayDate,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isDark ? BrandColors.softWhite : BrandColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Date navigation (right arrow) - disabled if today
          IconButton(
            icon: Icon(
              Icons.chevron_right,
              color: isToday
                  ? (isDark ? BrandColors.charcoal : BrandColors.stone)
                  : (isDark ? BrandColors.driftwood : BrandColors.charcoal),
            ),
            onPressed: isToday
                ? null
                : () {
                    final currentDate = ref.read(selectedJournalDateProvider);
                    ref.read(selectedJournalDateProvider.notifier).state =
                        currentDate.add(const Duration(days: 1));
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildJournalContent(BuildContext context, JournalDay journal) {
    if (journal.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: _refreshJournal,
      color: BrandColors.forest,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: journal.entries.length,
        itemBuilder: (context, index) {
          final entry = journal.entries[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: JournalEntryCard(
              entry: entry,
              audioPath: journal.getAudioPath(entry.id),
              onTap: () => _showEntryDetail(context, entry),
              onEdit: () => _editEntry(context, entry),
              onDelete: () => _deleteEntry(context, journal, entry),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 64,
              color: isDark ? BrandColors.driftwood : BrandColors.stone,
            ),
            const SizedBox(height: 16),
            Text(
              'Start your day',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? BrandColors.softWhite : BrandColors.charcoal,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Capture a thought, record a voice note,\nor just write something down.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: BrandColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                color: isDark ? BrandColors.softWhite : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: BrandColors.driftwood,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshJournal,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEntryDetail(BuildContext context, JournalEntry entry) {
    // TODO: Navigate to entry detail screen
    debugPrint('[JournalScreen] Show detail for entry: ${entry.id}');
  }

  void _editEntry(BuildContext context, JournalEntry entry) {
    // TODO: Show edit dialog
    debugPrint('[JournalScreen] Edit entry: ${entry.id}');
  }

  Future<void> _deleteEntry(
    BuildContext context,
    JournalDay journal,
    JournalEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: BrandColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = await ref.read(journalServiceFutureProvider.future);
      await service.deleteEntry(journal.date, entry.id);
      ref.invalidate(todayJournalProvider);
    }
  }
}
