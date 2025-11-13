import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/space_knowledge_service.dart';

/// Provider for the space knowledge service
final spaceKnowledgeServiceProvider = Provider<SpaceKnowledgeService>((ref) {
  return SpaceKnowledgeService();
});

/// Provider for linked captures in a specific space
/// Usage: ref.watch(spaceLinkedCapturesProvider(spacePath))
final spaceLinkedCapturesProvider =
    FutureProvider.family<List<LinkedCapture>, String>((ref, spacePath) async {
      final service = ref.watch(spaceKnowledgeServiceProvider);
      return service.getLinkedCaptures(spacePath: spacePath);
    });

/// Provider for space statistics
final spaceStatsProvider = FutureProvider.family<SpaceStats, String>((
  ref,
  spacePath,
) async {
  final service = ref.watch(spaceKnowledgeServiceProvider);
  return service.getSpaceStats(spacePath: spacePath);
});

/// Provider to check if a capture is linked to a space
final isCaptureLinkedProvider =
    FutureProvider.family<bool, ({String spacePath, String captureId})>((
      ref,
      params,
    ) async {
      final service = ref.watch(spaceKnowledgeServiceProvider);
      return service.isCaptureLinked(
        spacePath: params.spacePath,
        captureId: params.captureId,
      );
    });
