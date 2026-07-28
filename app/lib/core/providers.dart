import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/models.dart';

/// Explicit override, e.g.
///   flutter run --dart-define=GG_API_URL=http://192.168.1.50:8000
///
/// Set at run time rather than in source: the old Expo app had
/// `const BACKEND_URL = "http://10.0.0.243:8000"` baked into `utils/api.ts`,
/// which broke for anyone on a different LAN and could not be pointed at
/// staging without editing code.
const _explicitApiUrl = String.fromEnvironment('GG_API_URL');

/// Matches the backend's GG_AUTH_MODE=dev. Firebase Auth replaces this;
/// until then it keeps the app runnable with no Firebase config present.
const _devUser = String.fromEnvironment('GG_DEV_USER', defaultValue: 'dev-user');

/// Resolves the backend URL for the platform the app is actually running on.
///
/// The Android emulator runs behind its own NAT, so `localhost` resolves to
/// the emulator itself, not the developer's machine — every request fails with
/// connection-refused and looks like a backend outage. `10.0.2.2` is the
/// emulator's alias for the host loopback. iOS simulators share the host
/// network and need no translation.
String resolveApiUrl() {
  if (_explicitApiUrl.isNotEmpty) return _explicitApiUrl;
  if (kIsWeb) return 'http://localhost:8000';
  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: resolveApiUrl(),
    devUser: _devUser.isEmpty ? null : _devUser,
  );
});

final potsProvider = FutureProvider<List<Pot>>((ref) async {
  return ref.watch(apiClientProvider).listPots();
});

final potSnapshotProvider =
    FutureProvider.family<PotSnapshot, String>((ref, potId) async {
  return ref.watch(apiClientProvider).latest(potId);
});

final potSeriesProvider =
    FutureProvider.family<List<SeriesPoint>, String>((ref, potId) async {
  return ref.watch(apiClientProvider).readings(potId, bucket: '1h', hours: 48);
});
