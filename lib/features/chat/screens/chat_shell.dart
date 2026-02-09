import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import '../providers/chat_layout_provider.dart';
import '../widgets/session_list_panel.dart';
import '../widgets/chat_content_panel.dart';

/// Adaptive shell for the chat feature.
///
/// Uses LayoutBuilder to pick the right layout:
/// - **Mobile** (<600px): Just SessionListPanel; tapping a session pushes ChatScreen.
/// - **Tablet** (600–1199px): Two-column — session list + chat content side by side.
/// - **Desktop** (≥1200px): Three-column — sidebar + session list + chat content.
class ChatShell extends ConsumerWidget {
  const ChatShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = ChatLayoutBreakpoints.fromWidth(constraints.maxWidth);

        // Update the layout mode provider so child widgets can read it
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(chatLayoutModeProvider.notifier).state = mode;
        });

        switch (mode) {
          case ChatLayoutMode.mobile:
            return const _MobileLayout();
          case ChatLayoutMode.tablet:
            return const _TabletLayout();
          case ChatLayoutMode.desktop:
            return const _DesktopLayout();
        }
      },
    );
  }
}

/// Mobile: session list only; navigation handled by SessionListPanel push.
class _MobileLayout extends StatelessWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context) {
    return const SessionListPanel();
  }
}

/// Tablet: two-column layout — session list (narrow) + chat content (expanded).
class _TabletLayout extends StatelessWidget {
  const _TabletLayout();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                      : BrandColors.stone.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: const SessionListPanel(),
          ),
        ),
        const Expanded(child: ChatContentPanel()),
      ],
    );
  }
}

/// Desktop: three-column layout — sidebar + session list + chat content.
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // Sidebar (narrow nav rail)
        SizedBox(
          width: 64,
          child: _DesktopSidebar(isDark: isDark),
        ),
        // Session list
        SizedBox(
          width: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark
                      ? BrandColors.nightTextSecondary.withValues(alpha: 0.2)
                      : BrandColors.stone.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: const SessionListPanel(),
          ),
        ),
        // Chat content
        const Expanded(child: ChatContentPanel()),
      ],
    );
  }
}

/// Minimal sidebar for desktop layout — shows app icon and navigation icons.
class _DesktopSidebar extends StatelessWidget {
  final bool isDark;

  const _DesktopSidebar({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDark ? BrandColors.nightSurfaceElevated : BrandColors.softWhite,
      child: Column(
        children: [
          SizedBox(height: Spacing.lg),
          // App icon
          Icon(
            Icons.paragliding,
            size: 28,
            color: isDark ? BrandColors.nightForest : BrandColors.forest,
          ),
          SizedBox(height: Spacing.xl),
          // Chat (active)
          _SidebarIcon(
            icon: Icons.chat_bubble_outline,
            isActive: true,
            isDark: isDark,
            tooltip: 'Chat',
          ),
          SizedBox(height: Spacing.md),
          // Vault
          _SidebarIcon(
            icon: Icons.folder_outlined,
            isDark: isDark,
            tooltip: 'Vault',
          ),
          SizedBox(height: Spacing.md),
          // Brain
          _SidebarIcon(
            icon: Icons.psychology_outlined,
            isDark: isDark,
            tooltip: 'Brain',
          ),
          const Spacer(),
          // Settings
          _SidebarIcon(
            icon: Icons.settings_outlined,
            isDark: isDark,
            tooltip: 'Settings',
          ),
          SizedBox(height: Spacing.lg),
        ],
      ),
    );
  }
}

class _SidebarIcon extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isDark;
  final String tooltip;

  const _SidebarIcon({
    required this.icon,
    this.isActive = false,
    required this.isDark,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? (isDark
                  ? BrandColors.nightForest.withValues(alpha: 0.15)
                  : BrandColors.forest.withValues(alpha: 0.08))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 22,
          color: isActive
              ? (isDark ? BrandColors.nightForest : BrandColors.forest)
              : (isDark ? BrandColors.nightTextSecondary : BrandColors.stone),
        ),
      ),
    );
  }
}
