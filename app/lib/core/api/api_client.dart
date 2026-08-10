import 'package:dio/dio.dart';

import 'models.dart';

/// Thrown for any non-2xx response, carrying the backend's `detail` string.
///
/// The backend writes those messages for humans ("Soil is already at 88%
/// moisture. Watering now risks root rot.") — surfacing them beats a generic
/// "Request failed" every time.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, this.devUser, this.tokenProvider})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenProvider?.call();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        } else if (devUser != null) {
          // Matches GG_AUTH_MODE=dev on the backend, which rejects itself at
          // startup under GG_ENV=production.
          options.headers['X-Dev-User'] = devUser;
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;

  /// Set when GG_AUTH_MODE=dev, so the app runs without Firebase configured.
  final String? devUser;

  /// Called before each request to fetch a current Firebase ID token.
  final Future<String?> Function()? tokenProvider;

  Never _rethrow(DioException e) {
    final data = e.response?.data;
    final detail = data is Map<String, dynamic> ? data['detail'] : null;
    throw ApiException(
      e.response?.statusCode,
      detail?.toString() ?? e.message ?? 'Network error',
    );
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  // --- pots ---------------------------------------------------------------

  Future<List<Pot>> listPots() => _guard(() async {
        final r = await _dio.get<List<dynamic>>('/v1/pots');
        return (r.data ?? [])
            .map((e) => Pot.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<Pot> createPot(String name, {String? deviceId}) => _guard(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/v1/pots',
          data: {'name': name, if (deviceId != null) 'device_id': deviceId},
        );
        return Pot.fromJson(r.data!);
      });

  Future<Pot> updatePot(
    String potId, {
    String? name,
    bool? autoWaterEnabled,
    double? autoWaterThresholdPct,
  }) =>
      _guard(() async {
        final r = await _dio.patch<Map<String, dynamic>>(
          '/v1/pots/$potId',
          data: {
            if (name != null) 'name': name,
            if (autoWaterEnabled != null) 'auto_water_enabled': autoWaterEnabled,
            if (autoWaterThresholdPct != null)
              'auto_water_threshold_pct': autoWaterThresholdPct,
          },
        );
        return Pot.fromJson(r.data!);
      });

  Future<void> deletePot(String potId) =>
      _guard(() => _dio.delete<void>('/v1/pots/$potId'));

  // --- telemetry ----------------------------------------------------------

  Future<PotSnapshot> latest(String potId) => _guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/pots/$potId/latest');
        return PotSnapshot.fromJson(r.data!);
      });

  Future<List<SeriesPoint>> readings(
    String potId, {
    String bucket = '1h',
    int hours = 24,
  }) =>
      _guard(() async {
        final r = await _dio.get<Map<String, dynamic>>(
          '/v1/pots/$potId/readings',
          queryParameters: {'bucket': bucket, 'hours': hours},
        );
        return ((r.data?['points'] ?? []) as List<dynamic>)
            .map((e) => SeriesPoint.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<Health> health(String potId) => _guard(() async {
        final r = await _dio.get<Map<String, dynamic>>('/v1/pots/$potId/health');
        return Health.fromJson(r.data!);
      });

  // --- actions ------------------------------------------------------------

  /// Enqueues a watering command. Backend returns 202 with the queued command;
  /// 409 if the soil is already wet, 429 if watered too recently.
  Future<void> water(String potId, {required double durationSeconds}) =>
      _guard(() => _dio.post<Map<String, dynamic>>(
            '/v1/pots/$potId/water',
            data: {'duration_s': durationSeconds},
          ));

  Future<Map<String, dynamic>> claimDevice(String claimCode, {String? name}) =>
      _guard(() async {
        final r = await _dio.post<Map<String, dynamic>>(
          '/v1/devices/claim',
          data: {'claim_code': claimCode, if (name != null) 'name': name},
        );
        return r.data!;
      });
}
