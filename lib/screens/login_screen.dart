// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Demo App — Login Screen
// Simple rider selector. No production authentication needed for the demo.
// In production, rider identity is established through the platform's
// existing onboarding flow before PODCHAIN key registration occurs.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'task_list_screen.dart';

// Demo riders — simulating a small platform's delivery agent workforce
const _kDemoRiders = [
  {'id': 'rider_emeka_001', 'name': 'Emeka Okafor', 'zone': 'Lagos Island'},
  {'id': 'rider_fatima_002', 'name': 'Fatima Bello', 'zone': 'Victoria Island'},
  {'id': 'rider_chidi_003', 'name': 'Chidi Eze', 'zone': 'Lekki Phase 1'},
  {'id': 'rider_aisha_004', 'name': 'Aisha Mohammed', 'zone': 'Ikeja'},
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _selectedRiderId;
  bool _loading = false;
  String? _error;

  Future<void> _login(BuildContext context) async {
    if (_selectedRiderId == null) return;

    setState(() { _loading = true; _error = null; });

    try {
      final apiService = context.read<ApiService>();
      final appState = AppState(apiService: apiService);
      await appState.loginAs(_selectedRiderId!);

      if (!context.mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: appState,
            child: const TaskListScreen(),
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = 'Login failed: ${e.toString()}'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),

              // Header
              const Text(
                'PODCHAIN',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Delivery Agent\nSign In',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select your rider profile to begin.',
                style: TextStyle(color: Color(0xFF666666)),
              ),
              const SizedBox(height: 40),

              // Rider selector
              const Text(
                'Select Rider',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 12),

              ..._kDemoRiders.map((rider) => _RiderTile(
                id: rider['id']!,
                name: rider['name']!,
                zone: rider['zone']!,
                selected: _selectedRiderId == rider['id'],
                onTap: () => setState(() => _selectedRiderId = rider['id']),
              )),

              const Spacer(),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),

              FilledButton(
                onPressed: _selectedRiderId == null || _loading ? null : () => _login(context),
                child: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue'),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Demo system — no real authentication required',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiderTile extends StatelessWidget {
  final String id;
  final String name;
  final String zone;
  final bool selected;
  final VoidCallback onTap;

  const _RiderTile({
    required this.id,
    required this.name,
    required this.zone,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111111) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF111111) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: selected ? Colors.white24 : const Color(0xFFDDDDDD),
              child: Text(
                name[0],
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    zone,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white70 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
