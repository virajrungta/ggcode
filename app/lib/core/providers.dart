import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/models.dart';

/// Base URL of the backend.
///
/// Override at run time rather than editing source — the old Expo app had
/// `const BACKEND_URL = "http://10.0.0.243:8000"` hardcoded in `utils/api.ts`,
/// which broke for every developer whose LAN differed and could not be pointed
/// at staging without a code change.
///
///   flutter run --dart-define=GG_API_URL=http://192.168.1.50:8000
const _apiUrl = String.fromEnvironment(
  'GG_API_URL',
  defaultValue: 'http://localhost:8000',
);

/// Matches the backend's GG_AUTH_MODE=dev. Firebase Auth replaces this in
/// Phase 4; until the platform config files exist, this keeps the app runnable.
const _devUser = String.fromEnvironment('GG_DEV_USER', defaultValue: 'dev-user');

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: _apiUrl, devUser: _devUser.isEmpty ? null : _devUser);
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
