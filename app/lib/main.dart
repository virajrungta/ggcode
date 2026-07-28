import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/tokens.dart';
import 'app/shell.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/trends/trends_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The app is dark-only by design, so the status bar icons are always light.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
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
      theme: GGTheme.dark,
      home: const _Root(),
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
