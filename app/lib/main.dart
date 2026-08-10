import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/auth/sign_in_screen.dart';

import 'design/tokens.dart';
import 'app/shell.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/trends/trends_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads GoogleService-Info.plist / google-services.json bundled at build
  // time; no keys in source.
  await Firebase.initializeApp();

  // Light app, so the status bar needs dark icons. (The two flags are
  // inverted relative to each other: iOS wants the *bar* brightness.)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: GreenGeniusApp()));
}

class GreenGeniusApp extends StatelessWidget {
  const GreenGeniusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GreenGenius',
      debugShowCheckedModeBanner: false,
      theme: GGTheme.light,
      home: const _AuthGate(),
    );
  }
}


class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    return AppShell(
      tabs: [
        ShellTab(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: 'Home',
          builder: (_) => const DashboardScreen(),
        ),
        ShellTab(
          icon: Icons.insights_outlined,
          activeIcon: Icons.insights_rounded,
          label: 'Trends',
          builder: (_) => const TrendsScreen(),
        ),
        ShellTab(
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          label: 'Settings',
          builder: (_) => const SettingsScreen(),
        ),
      ],
    );
  }
}

/// Chooses between sign-in and the app based on Firebase auth state.
///
/// Driven by the authStateChanges stream rather than a one-off check, so a
/// token expiring or a sign-out elsewhere lands the user back on sign-in
/// without needing a restart.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          loading: () => const Scaffold(
            backgroundColor: GGColors.bg,
            body: Center(child: CircularProgressIndicator()),
          ),
          // A failure to read auth state is not a reason to lock someone out
          // of a local-network app; fall through to sign-in.
          error: (_, __) => const SignInScreen(),
          data: (user) => user == null ? const SignInScreen() : const _Root(),
        );
  }
}
