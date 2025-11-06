import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:git2dart/git2dart.dart';

import 'package:app/core/services/git/git_service.dart';
import 'package:app/features/files/providers/local_file_browser_provider.dart';

/// Git sync state
class GitSyncState {
  final bool isEnabled;
  final String? repositoryUrl;
  final String? currentBranch;
  final bool hasRemote;
  final bool isSyncing;
  final String? lastError;
  final DateTime? lastSyncTime;

  const GitSyncState({
    this.isEnabled = false,
    this.repositoryUrl,
    this.currentBranch,
    this.hasRemote = false,
    this.isSyncing = false,
    this.lastError,
    this.lastSyncTime,
  });

  GitSyncState copyWith({
    bool? isEnabled,
    String? repositoryUrl,
    String? currentBranch,
    bool? hasRemote,
    bool? isSyncing,
    String? lastError,
    DateTime? lastSyncTime,
  }) {
    return GitSyncState(
      isEnabled: isEnabled ?? this.isEnabled,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      currentBranch: currentBranch ?? this.currentBranch,
      hasRemote: hasRemote ?? this.hasRemote,
      isSyncing: isSyncing ?? this.isSyncing,
      lastError: lastError,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// Git sync notifier
class GitSyncNotifier extends StateNotifier<GitSyncState> {
  GitSyncNotifier(this._ref) : super(const GitSyncState());

  final Ref _ref;
  final GitService _gitService = GitService.instance;
  Repository? _repository;

  /// Initialize Git sync by checking if vault is a Git repository
  Future<void> initialize() async {
    final fileSystemService = _ref.read(fileSystemServiceProvider);
    final vaultPath = await fileSystemService.getRootPath();
    final isGitRepo = await _gitService.isGitRepository(vaultPath);

    if (isGitRepo) {
      _repository = await _gitService.openRepository(vaultPath);
      if (_repository != null) {
        await _updateStatus();
      }
    }
  }

  /// Setup Git sync with a GitHub repository
  Future<bool> setupGitSync({
    required String repositoryUrl,
    required String githubToken,
  }) async {
    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      // Set GitHub token
      _gitService.setGitHubToken(githubToken);

      final fileSystemService = _ref.read(fileSystemServiceProvider);
      final vaultPath = await fileSystemService.getRootPath();
      final isGitRepo = await _gitService.isGitRepository(vaultPath);

      if (!isGitRepo) {
        // Initialize git repo in existing vault directory
        debugPrint('[GitSync] Initializing git repository in: $vaultPath');
        _repository = await _gitService.initializeRepository(vaultPath);

        if (_repository == null) {
          state = state.copyWith(
            isSyncing: false,
            lastError: 'Failed to initialize repository',
          );
          return false;
        }

        // Add remote
        debugPrint('[GitSync] Adding remote: $repositoryUrl');
        final remoteAdded = await _gitService.addRemote(
          repo: _repository!,
          name: 'origin',
          url: repositoryUrl,
        );

        if (!remoteAdded) {
          state = state.copyWith(
            isSyncing: false,
            lastError: 'Failed to add remote',
          );
          return false;
        }

        // Check if we have any commits locally
        final hasCommits = await _gitService.hasCommits(repo: _repository!);

        if (!hasCommits) {
          // No commits yet - create initial commit with existing files
          debugPrint('[GitSync] No commits found, creating initial commit...');

          // Add all existing files
          debugPrint('[GitSync] Adding all files to index...');
          final addedAll = await _gitService.addAll(repo: _repository!);

          if (!addedAll) {
            debugPrint('[GitSync] Warning: Failed to add files to index');
          }

          // Create initial commit
          debugPrint('[GitSync] Creating initial commit...');
          final commitSha = await _gitService.commit(
            repo: _repository!,
            message: 'Initial commit - Parachute vault setup',
            authorName: 'Parachute',
            authorEmail: 'parachute@local',
          );

          if (commitSha == null) {
            debugPrint(
              '[GitSync] ⚠️  Warning: Failed to create initial commit',
            );
          } else {
            debugPrint('[GitSync] ✅ Initial commit created: $commitSha');
          }
        }

        // Get current branch name
        final currentBranch = _gitService.getCurrentBranch(repo: _repository!);
        final branchName = currentBranch ?? 'main';
        debugPrint('[GitSync] Using branch: $branchName');

        // Try to pull from remote (in case repo already has content)
        debugPrint('[GitSync] Pulling from remote...');
        final pulled = await _gitService.pull(
          repo: _repository!,
          branchName: branchName,
        );

        if (!pulled) {
          debugPrint(
            '[GitSync] Pull failed (remote might be empty), will push local commits...',
          );
        }

        // Push to remote
        debugPrint('[GitSync] Pushing to remote...');
        final pushed = await _gitService.push(
          repo: _repository!,
          branchName: branchName,
        );

        if (pushed) {
          debugPrint('[GitSync] ✅ Successfully pushed to remote');
        } else {
          debugPrint('[GitSync] ⚠️  Warning: Failed to push to remote');
        }
      } else {
        // Open existing repository
        _repository = await _gitService.openRepository(vaultPath);
      }

      await _updateStatus();
      state = state.copyWith(
        isEnabled: true,
        repositoryUrl: repositoryUrl,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      );

      return true;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Push local changes to remote
  Future<bool> push() async {
    if (_repository == null) return false;

    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      final success = await _gitService.push(repo: _repository!);

      if (success) {
        await _updateStatus();
        state = state.copyWith(isSyncing: false, lastSyncTime: DateTime.now());
      } else {
        state = state.copyWith(isSyncing: false, lastError: 'Push failed');
      }

      return success;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Pull changes from remote
  Future<bool> pull() async {
    if (_repository == null) return false;

    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      final success = await _gitService.pull(repo: _repository!);

      if (success) {
        await _updateStatus();
        state = state.copyWith(isSyncing: false, lastSyncTime: DateTime.now());
      } else {
        state = state.copyWith(isSyncing: false, lastError: 'Pull failed');
      }

      return success;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Sync (pull then push)
  Future<bool> sync() async {
    if (_repository == null) return false;

    try {
      state = state.copyWith(isSyncing: true, lastError: null);

      // Check if we have any commits locally
      final hasCommits = await _gitService.hasCommits(repo: _repository!);

      if (!hasCommits) {
        // No commits yet - create initial commit with existing files
        debugPrint('[GitSync] No commits found, creating initial commit...');

        // Add all existing files
        final addedAll = await _gitService.addAll(repo: _repository!);
        if (!addedAll) {
          debugPrint('[GitSync] Warning: Failed to add files to index');
        }

        // Create initial commit
        final commitSha = await _gitService.commit(
          repo: _repository!,
          message: 'Initial commit - Parachute vault setup',
          authorName: 'Parachute',
          authorEmail: 'parachute@local',
        );

        if (commitSha != null) {
          debugPrint('[GitSync] ✅ Initial commit created: $commitSha');
        }
      }

      // Get current branch name
      final currentBranch = _gitService.getCurrentBranch(repo: _repository!);
      final branchName = currentBranch ?? 'main';
      debugPrint('[GitSync] Using branch: $branchName');

      // Try to pull (may fail if remote is empty)
      final pullSuccess = await _gitService.pull(
        repo: _repository!,
        branchName: branchName,
      );
      if (!pullSuccess) {
        debugPrint(
          '[GitSync] Pull failed (remote might be empty), continuing with push...',
        );
      }

      // Always push, even if pull failed
      final pushSuccess = await _gitService.push(
        repo: _repository!,
        branchName: branchName,
      );
      if (!pushSuccess) {
        state = state.copyWith(
          isSyncing: false,
          lastError: 'Push failed during sync',
        );
        return false;
      }

      await _updateStatus();
      state = state.copyWith(isSyncing: false, lastSyncTime: DateTime.now());

      return true;
    } catch (e) {
      state = state.copyWith(isSyncing: false, lastError: e.toString());
      return false;
    }
  }

  /// Disable Git sync
  Future<void> disable() async {
    _gitService.clearGitHubToken();
    _repository = null;
    state = const GitSyncState();
  }

  /// Update sync status from repository
  Future<void> _updateStatus() async {
    if (_repository == null) return;

    final status = await _gitService.getSyncStatus(_repository!);

    state = state.copyWith(
      hasRemote: status['hasRemote'] as bool,
      currentBranch: status['currentBranch'] as String?,
    );
  }
}

/// Git sync provider
final gitSyncProvider = StateNotifierProvider<GitSyncNotifier, GitSyncState>((
  ref,
) {
  return GitSyncNotifier(ref);
});
