import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/data_service.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

class AppThemeAssets {
  static const String bgImage = 'assets/images/bg.png';
  static const String lccLogo = 'assets/images/lcc_logo.png';
  static const String lccIcon = 'assets/images/lcc.png';
  static const String splashLogo = 'assets/images/lcc2026.png';
}

class AppColors {
  static const primaryStart = Color(0xFF1e3a8a);
  static const primaryEnd = Color(0xFF3b82f6);
  static const overlayStart = Color(0xCC0f172a);
  static const overlayEnd = Color(0x991e3a8a);
}

Widget buildAppBackground({required Widget child, double blur = 0}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryStart, Color(0xFF0b1e4d), Color(0xFF061236)],
          ),
        ),
      ),
      Image.asset(
        AppThemeAssets.bgImage,
        fit: BoxFit.cover,
        opacity: const AlwaysStoppedAnimation(0.18),
      ),
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.overlayStart,
              AppColors.overlayEnd,
            ],
          ),
        ),
      ),
      child,
    ],
  );
}

/// Logo screen shown first while the app boots (before Login / Home).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: buildAppBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x33000000),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(
                  AppThemeAssets.splashLogo,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.school,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Colors.white, Color(0xFFBFDBFE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: const Text(
                  'Attendify',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Loading…',
                style: TextStyle(color: Color(0xFFCFE0FF), fontSize: 14),
              ),
              const SizedBox(height: 26),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [SplashScreen] first, then routes to Login or Home once the
/// splash delay has elapsed and the stored session has been restored.
class SplashGate extends ConsumerStatefulWidget {
  const SplashGate({super.key, this.minDuration = const Duration(milliseconds: 2200)});

  final Duration minDuration;

  @override
  ConsumerState<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends ConsumerState<SplashGate> {
  bool _splashElapsed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minDuration, () {
      if (mounted) setState(() => _splashElapsed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    // Keep showing the splash until both the minimum delay has passed and the
    // persisted session has finished restoring, so we never flash Login first.
    if (!_splashElapsed || authState.isLoading) return const SplashScreen();
    final isAuthenticated = authState.maybeWhen(
      data: (user) => user != null,
      orElse: () => false,
    );
    return isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DataService.init();
  runApp(
    ProviderScope(
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Attendify',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3b82f6),
          primary: const Color(0xFF3b82f6),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: const Color(0xFF1F2333),
              displayColor: const Color(0xFF1F2333),
            ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        tabBarTheme: const TabBarThemeData(
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: TextStyle(fontWeight: FontWeight.w700),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shadowColor: Color(0x14000000),
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF3b82f6), width: 1.5),
          ),
          labelStyle: const TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w500,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(fontSize: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF3b82f6),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1e3a8a),
            side: const BorderSide(color: Color(0xFF3b82f6)),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        chipTheme: ChipThemeData.fromDefaults(
          secondaryColor: const Color(0xFFDBEAFE),
          brightness: Brightness.light,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      ),
      home: const SplashGate(),
    );
  }
}
