import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/features/chat/models/workspace.dart';
import 'package:parachute/features/chat/providers/workspace_providers.dart';
import 'package:parachute/features/settings/models/trust_level.dart';

/// Workspace management section in Settings.
///
/// Lists workspaces with edit/delete actions and a create button.
class WorkspaceManagementSection extends ConsumerWidget {
  const WorkspaceManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final workspacesAsync = ref.watch(workspacesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(
              Icons.workspaces_outline,
              size: 20,
              color: isDark ? BrandColors.nightForest : BrandColors.forest,
            ),
            SizedBox(width: Spacing.sm),
            Text(
              'Workspaces',
              style: TextStyle(
                fontSize: TypographyTokens.titleMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showCreateDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
            ),
          ],
        ),
        SizedBox(height: Spacing.xs),
        Text(
          'Named capability sets that control what tools and permissions are available.',
          style: TextStyle(
            fontSize: TypographyTokens.bodySmall,
            color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
          ),
        ),
        SizedBox(height: Spacing.md),

        // Workspace list
        workspacesAsync.when(
          data: (workspaces) {
            if (workspaces.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.lg),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.workspaces_outline,
                        size: 40,
                        color: isDark
                            ? BrandColors.nightTextSecondary.withValues(alpha: 0.4)
                            : BrandColors.stone.withValues(alpha: 0.4),
                      ),
                      SizedBox(height: Spacing.sm),
                      Text(
                        'No workspaces yet',
                        style: TextStyle(
                          color: isDark ? BrandColors.nightTextSecondary : BrandColors.stone,
                        ),
                      ),
                      SizedBox(height: Spacing.xs),
                      Text(
                        'Create a workspace to organize sessions with shared settings',
                        style: TextStyle(
                          fontSize: TypographyTokens.bodySmall,
                          color: isDark
                              ? BrandColors.nightTextSecondary.withValues(alpha: 0.7)
                              : BrandColors.stone.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: workspaces
                  .map((ws) => _WorkspaceTile(workspace: ws, isDark: isDark))
                  .toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Padding(
            padding: EdgeInsets.all(Spacing.md),
            child: Text(
              'Failed to load workspaces: $error',
              style: TextStyle(color: BrandColors.error),
            ),
          ),
        ),
      ],
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => _CreateWorkspaceDialog(
        onCreated: () => ref.invalidate(workspacesProvider),
      ),
    );
  }
}

/// Individual workspace tile with edit/delete actions.
class _WorkspaceTile extends ConsumerWidget {
  final Workspace workspace;
  final bool isDark;

  const _WorkspaceTile({required this.workspace, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: EdgeInsets.only(bottom: Spacing.sm),
      padding: EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : Colors.white,
        borderRadius: Radii.card,
        border: Border.all(
          color: isDark
              ? BrandColors.nightTextSecondary.withValues(alpha: 0.15)
              : BrandColors.stone.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          // Trust level icon
          Icon(
            _trustIcon(workspace.trustLevel),
            size: 20,
            color: _trustColor(workspace.trustLevel),
          ),
          SizedBox(width: Spacing.md),
          // Workspace info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workspace.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    _Badge(
                      label: workspace.trustLevel,
                      color: _trustColor(workspace.trustLevel),
                      isDark: isDark,
                    ),
                    if (workspace.model != null) ...[
                      SizedBox(width: Spacing.xs),
                      _Badge(
                        label: workspace.model!,
                        color: isDark ? BrandColors.nightTurquoise : BrandColors.turquoise,
                        isDark: isDark,
                      ),
                    ],
                  ],
                ),
                if (workspace.description.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    workspace.description,
                    style: TextStyle(
                      fontSize: TypographyTokens.bodySmall,
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Actions
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.stone,
            ),
            onSelected: (value) {
              if (value == 'edit') {
                _showEditDialog(context, ref);
              } else if (value == 'delete') {
                _confirmDelete(context, ref);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: BrandColors.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _trustIcon(String trust) {
    switch (trust) {
      case 'sandboxed':
        return Icons.shield_outlined;
      case 'vault':
        return Icons.lock_outline;
      default:
        return Icons.security;
    }
  }

  Color _trustColor(String trust) {
    switch (trust) {
      case 'sandboxed':
        return BrandColors.error;
      case 'vault':
        return BrandColors.warning;
      default:
        return BrandColors.forest;
    }
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => _EditWorkspaceDialog(
        workspace: workspace,
        onSaved: () => ref.invalidate(workspacesProvider),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${workspace.name}"?'),
        content: const Text(
          'Sessions in this workspace will be unlinked but not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final service = ref.read(workspaceServiceProvider);
                await service.deleteWorkspace(workspace.slug);
                ref.invalidate(workspacesProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: BrandColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Small colored badge widget.
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;

  const _Badge({required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: TypographyTokens.labelSmall,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

/// Dialog for creating a new workspace.
class _CreateWorkspaceDialog extends ConsumerStatefulWidget {
  final VoidCallback onCreated;

  const _CreateWorkspaceDialog({required this.onCreated});

  @override
  ConsumerState<_CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends ConsumerState<_CreateWorkspaceDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _dirController = TextEditingController();
  String _trustLevel = 'full';
  String? _model;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Workspace'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _dirController,
              decoration: const InputDecoration(
                labelText: 'Working directory (optional)',
                hintText: 'e.g., Projects/my-app',
              ),
            ),
            SizedBox(height: Spacing.md),
            DropdownButtonFormField<String>(
              value: _trustLevel,
              decoration: const InputDecoration(labelText: 'Trust level'),
              items: TrustLevel.values.map((tl) => DropdownMenuItem(
                value: tl.name,
                child: Text(tl.displayName),
              )).toList(),
              onChanged: (val) => setState(() => _trustLevel = val ?? 'full'),
            ),
            SizedBox(height: Spacing.md),
            DropdownButtonFormField<String?>(
              value: _model,
              decoration: const InputDecoration(labelText: 'Default model'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Server default')),
                DropdownMenuItem(value: 'sonnet', child: Text('Sonnet')),
                DropdownMenuItem(value: 'opus', child: Text('Opus')),
                DropdownMenuItem(value: 'haiku', child: Text('Haiku')),
              ],
              onChanged: (val) => setState(() => _model = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final service = ref.read(workspaceServiceProvider);
      await service.createWorkspace(
        name: name,
        description: _descController.text.trim(),
        trustLevel: _trustLevel,
        workingDirectory: _dirController.text.trim().isEmpty ? null : _dirController.text.trim(),
        model: _model,
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create workspace: $e')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }
}

/// Dialog for editing an existing workspace.
class _EditWorkspaceDialog extends ConsumerStatefulWidget {
  final Workspace workspace;
  final VoidCallback onSaved;

  const _EditWorkspaceDialog({required this.workspace, required this.onSaved});

  @override
  ConsumerState<_EditWorkspaceDialog> createState() => _EditWorkspaceDialogState();
}

class _EditWorkspaceDialogState extends ConsumerState<_EditWorkspaceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _dirController;
  late String _trustLevel;
  late String? _model;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workspace.name);
    _descController = TextEditingController(text: widget.workspace.description);
    _dirController = TextEditingController(text: widget.workspace.workingDirectory ?? '');
    _trustLevel = widget.workspace.trustLevel;
    _model = widget.workspace.model;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _dirController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit "${widget.workspace.name}"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _dirController,
              decoration: const InputDecoration(
                labelText: 'Working directory',
                hintText: 'e.g., Projects/my-app',
              ),
            ),
            SizedBox(height: Spacing.md),
            DropdownButtonFormField<String>(
              value: _trustLevel,
              decoration: const InputDecoration(labelText: 'Trust level'),
              items: TrustLevel.values.map((tl) => DropdownMenuItem(
                value: tl.name,
                child: Text(tl.displayName),
              )).toList(),
              onChanged: (val) => setState(() => _trustLevel = val ?? 'full'),
            ),
            SizedBox(height: Spacing.md),
            DropdownButtonFormField<String?>(
              value: _model,
              decoration: const InputDecoration(labelText: 'Default model'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Server default')),
                DropdownMenuItem(value: 'sonnet', child: Text('Sonnet')),
                DropdownMenuItem(value: 'opus', child: Text('Opus')),
                DropdownMenuItem(value: 'haiku', child: Text('Haiku')),
              ],
              onChanged: (val) => setState(() => _model = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final service = ref.read(workspaceServiceProvider);
      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'trust_level': _trustLevel,
        'working_directory': _dirController.text.trim().isEmpty ? null : _dirController.text.trim(),
        'model': _model,
      };
      await service.updateWorkspace(widget.workspace.slug, updates);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }
}
