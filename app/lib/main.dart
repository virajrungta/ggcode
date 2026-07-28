import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design/tokens.dart';
import 'features/dashboard/dashboard_screen.dart';

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
      theme: buildTheme(),
      home: const DashboardScreen(),
    );
  }
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: GGColors.bgDeep,
    colorScheme: base.colorScheme.copyWith(
      primary: GGColors.volt,
      secondary: GGColors.cyan,
      surface: GGColors.surface,
      error: GGColors.bad,
      onPrimary: GGColors.bgDeep,
    ),
    // Surfaces are translucent glass over the mesh background, so opaque
    // Material defaults would flatten the whole effect.
    canvasColor: Colors.transparent,
    cardColor: Colors.transparent,
    dividerColor: Colors.white.withValues(alpha: 0.08),
    splashColor: GGColors.volt.withValues(alpha: 0.08),
    highlightColor: GGColors.volt.withValues(alpha: 0.04),
  );
}
