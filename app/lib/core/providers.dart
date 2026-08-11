import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'auth/auth_service.dart';
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
/// Empty by default. The backend runs GG_AUTH_MODE=firebase both locally and
/// deployed, so the header is dead weight — and a default that ships a
/// dev-auth header in a release build is the wrong thing to have lying around.
const _devUser = String.fromEnvironment('GG_DEV_USER');

/// The deployed backend. This is the default so a build installed on a real
/// phone works anywhere, with no laptop running and no --dart-define.
///
/// It used to default to localhost, which on a physical device means the
/// device itself: the app worked only while it happened to be pointed at a
/// developer machine on the same Wi-Fi, and went dead the moment that machine
/// slept.
const _deployedApiUrl = 'https://ggcode-nkdo.onrender.com';

/// Resolves the backend URL for the platform the app is actually running on.
///
/// Emulators and simulators still get a loopback address, because that is
/// where a developer's backend actually is. The Android emulator runs behind
/// its own NAT, so `localhost` resolves to the emulator itself rather than the
/// host — every request fails with connection-refused and looks like a backend
/// outage. `10.0.2.2` is its alias for the host loopback.
///
/// A physical device gets the deployed URL, since nothing on the phone is
/// listening on port 8000 and the host may not even be awake.
String resolveApiUrl() {
  if (_explicitApiUrl.isNotEmpty) return _explicitApiUrl;
  if (kIsWeb) return 'http://localhost:8000';

  // Emulator/simulator detection is deliberately not attempted here: a release
  // build is what ships to a phone, and a debug build is what runs on a
  // simulator, so the build mode is the reliable signal.
  if (kReleaseMode) return _deployedApiUrl;

  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Rebuilds when sign-in state changes, so the client is never left holding a
/// signed-out user's token.
final authStateProvider = StreamProvider((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authServiceProvider);
  return ApiClient(
    baseUrl: resolveApiUrl(),
    devUser: _devUser.isEmpty ? null : _devUser,
    // Resolved per request rather than cached: Firebase ID tokens expire
    // after an hour, and getIdToken() refreshes near expiry. A token captured
    // once starts returning 401s after an hour of use.
    tokenProvider: auth.idToken,
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
