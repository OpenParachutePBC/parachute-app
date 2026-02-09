import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/services/computer_server_service.dart';

/// Provider for the ComputerServerService singleton
final computerServerServiceProvider = Provider<ComputerServerService>((ref) {
  return ComputerServerService();
});

/// Provider for server connectivity status
final serverConnectedProvider = FutureProvider<bool>((ref) async {
  final server = ref.watch(computerServerServiceProvider);
  await server.initialize();
  return server.isServerReachable();
});
