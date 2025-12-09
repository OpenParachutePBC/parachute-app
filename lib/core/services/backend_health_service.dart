import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

/// Service for checking backend server health
class BackendHealthService {
  final Dio _dio;

  BackendHealthService()
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  /// Check if backend server is reachable and healthy
  Future<ServerHealthStatus> checkHealth(String serverUrl) async {
    try {
      debugPrint('[BackendHealth] Checking health at: $serverUrl/health');

      final response = await _dio.get(
        '$serverUrl/health',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final status = data['status'] as String?;
        final version = data['version'] as String?;
        final acpEnabled = data['acp_enabled'] as bool? ?? false;

        if (status == 'ok') {
          debugPrint(
            '[BackendHealth] ✅ Server healthy - version: $version, ACP: $acpEnabled',
          );
          return ServerHealthStatus(
            isHealthy: true,
            message: 'Connected',
            version: version,
            acpEnabled: acpEnabled,
          );
        }
      }

      debugPrint(
        '[BackendHealth] ⚠️ Unexpected response: ${response.statusCode}',
      );
      return ServerHealthStatus(
        isHealthy: false,
        message: 'Server responded with status ${response.statusCode}',
      );
    } on DioException catch (e) {
      debugPrint(
        '[BackendHealth] ❌ Connection failed: ${e.type} - ${e.message}',
      );

      String message;
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          message = 'Connection timeout';
          break;
        case DioExceptionType.connectionError:
          message = 'Cannot reach server';
          break;
        default:
          message = 'Connection error: ${e.message}';
      }

      return ServerHealthStatus(
        isHealthy: false,
        message: message,
        error: e.toString(),
      );
    } catch (e) {
      debugPrint('[BackendHealth] ❌ Unexpected error: $e');
      return ServerHealthStatus(
        isHealthy: false,
        message: 'Unexpected error',
        error: e.toString(),
      );
    }
  }
}

/// Health status of the backend server
class ServerHealthStatus {
  final bool isHealthy;
  final String message;
  final String? version;
  final bool? acpEnabled;
  final String? error;

  ServerHealthStatus({
    required this.isHealthy,
    required this.message,
    this.version,
    this.acpEnabled,
    this.error,
  });

  String get displayMessage {
    if (isHealthy) {
      final versionInfo = version != null ? ' (v$version)' : '';
      final acpInfo = acpEnabled == true ? ' • ACP enabled' : '';
      return 'Connected$versionInfo$acpInfo';
    }
    return message;
  }
}
