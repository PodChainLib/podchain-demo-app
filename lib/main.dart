// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Demo App — main.dart
// Application entry point. Sets up providers and launches the login screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:podchain_flutter/podchain_flutter.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';

// In the demo, the API runs locally. Update this for remote testing.
const _kBaseUrl = 'http://10.0.2.2:3000'; // Android emulator → host localhost

void main() {
  runApp(const PodChainDemoApp());
}

class PodChainDemoApp extends StatelessWidget {
  const PodChainDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(
          create: (_) => ApiService(baseUrl: _kBaseUrl),
        ),
      ],
      child: MaterialApp(
        title: 'PODCHAIN Demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF111111),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF111111),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111111),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        home: const LoginScreen(),
      ),
    );
  }
}

/// App-level state: holds the active rider ID and PodChainFlutter instance.
class AppState extends ChangeNotifier {
  String? _riderId;
  PodChainFlutter? _podchain;
  final ApiService _apiService;

  AppState({required ApiService apiService}) : _apiService = apiService;

  String? get riderId => _riderId;
  PodChainFlutter? get podchain => _podchain;

  Future<void> loginAs(String riderId) async {
    _riderId = riderId;

    _podchain = PodChainFlutter(
      riderId: riderId,
      onSubmit: _apiService.submitProof,
    );

    // On first login for this rider, generate key and register with platform.
    final hasKey = await _podchain!.hasKey();
    if (!hasKey) {
      final publicKey = await _podchain!.generateOrRetrievePublicKey();
      await _apiService.registerKey(riderId: riderId, publicKey: publicKey);
    }

    notifyListeners();
  }

  void logout() {
    _riderId = null;
    _podchain = null;
    notifyListeners();
  }
}
