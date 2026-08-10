import 'package:firebase_auth/firebase_auth.dart';

/// Firebase authentication.
///
/// Firebase is the identity provider only. Sensor data lives in Postgres —
/// Firestore bills per document write and has no time-bucketed aggregation,
/// which suits 40k+ readings a month badly.
///
/// The backend verifies the ID token locally against Google's JWKS, so no
/// Admin SDK and no round trip per request. See `backend/app/core/auth.py`.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;

  /// Fetches the current ID token for the Authorization header.
  ///
  /// Firebase ID tokens expire after an hour. `getIdToken()` refreshes
  /// automatically when close to expiry, so this is called before each
  /// request rather than cached — a cached token silently starts returning
  /// 401s after an hour of use.
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  Future<User> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return cred.user!;
  }

  Future<User> signUp(String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return cred.user!;
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() => _auth.signOut();

  /// Turns a FirebaseAuthException into something worth showing a person.
  ///
  /// The raw codes are developer-facing: `invalid-credential` and
  /// `operation-not-allowed` mean nothing to a user, and the second one is a
  /// console misconfiguration rather than anything they did wrong.
  static String describeError(Object error) {
    if (error is! FirebaseAuthException) {
      return 'Something went wrong. Please try again.';
    }
    return switch (error.code) {
      'invalid-email' => 'That does not look like an email address.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Email or password is incorrect.',
      'email-already-in-use' =>
        'An account already exists for that email. Try signing in.',
      'weak-password' => 'Use at least 6 characters.',
      'too-many-requests' =>
        'Too many attempts. Wait a moment and try again.',
      'network-request-failed' =>
        'No connection. Check your network and try again.',
      // Not the user's fault: Email/Password sign-in is disabled in the
      // Firebase console. Named plainly so it is not mistaken for bad input.
      'operation-not-allowed' =>
        'Email sign-in is not enabled for this app yet.',
      _ => error.message ?? 'Sign-in failed. Please try again.',
    };
  }
}
