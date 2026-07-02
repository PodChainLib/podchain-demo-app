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

const _kRiderProfiles = <String, Map<String, String>>{
  'rider_emeka_001': {'name': 'Emeka Okafor', 'zone': 'Lagos Island'},
  'rider_fatima_002': {'name': 'Fatima Bello', 'zone': 'Victoria Island'},
  'rider_chidi_003': {'name': 'Chidi Eze', 'zone': 'Lekki Phase 1'},
  'rider_aisha_004': {'name': 'Aisha Mohammed', 'zone': 'Ikeja'},
};

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _selectedRiderId;
  List<String> _registeredRiders = [];
  bool _loadingRiders = true;
  String? _riderLoadError;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRegisteredRiders();
  }

  Future<void> _loadRegisteredRiders() async {
    setState(() {
      _loadingRiders = true;
      _riderLoadError = null;
    });

    try {
      final apiService = context.read<ApiService>();
      final riders = await apiService.getRegisteredRiders();
      if (!mounted) return;

      setState(() {
        _registeredRiders = riders;
        if (_selectedRiderId != null &&
            !_availableRiderIds.contains(_selectedRiderId)) {
          _selectedRiderId = null;
        }
      });
    } on ApiException catch (e) {
      setState(() {
        _riderLoadError = e.message;
      });
    } catch (e) {
      setState(() {
        _riderLoadError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRiders = false;
        });
      }
    }
  }

  Future<void> _login(BuildContext context) async {
    if (_selectedRiderId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

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
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = 'Login failed: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRiders = _availableRiderIds.isNotEmpty;

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
              Expanded(child: _buildRiderSelector()),

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
                    style:
                        const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),

              FilledButton(
                onPressed: _selectedRiderId == null || _loading || !hasRiders
                    ? null
                    : () => _login(context),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
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

  Widget _buildRiderSelector() {
    if (_loadingRiders) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_riderLoadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              _riderLoadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF666666)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadRegisteredRiders,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final availableRiderIds = _availableRiderIds;

    if (availableRiderIds.isEmpty) {
      return _buildNoRidersView();
    }

    return ListView(
      children: availableRiderIds.map((riderId) {
        final profile = _kRiderProfiles[riderId];
        final name = profile?['name'] ?? _labelFromRiderId(riderId);
        final registered = _registeredRiders.contains(riderId);
        final zone = profile?['zone'] ?? 'Registered rider';

        return _RiderTile(
          id: riderId,
          name: name,
          zone: zone,
          registered: registered,
          selected: _selectedRiderId == riderId,
          onTap: () => setState(() => _selectedRiderId = riderId),
        );
      }).toList(),
    );
  }

  List<String> get _availableRiderIds {
    final ids = <String>{
      ..._kRiderProfiles.keys,
      ..._registeredRiders,
    }.toList()
      ..sort();
    return ids;
  }

  Widget _buildNoRidersView() {
    const bootstrapUrl = 'http://127.0.0.1:3000/demo/bootstrap';
    const sampleBody = '{\n'
        '  "riderId": "rider_aisha_004",\n'
        '  "publicKey": { "kty": "EC", "crv": "P-256", "x": "...", "y": "..." },\n'
        '  "tiers": [1, 2, 3],\n'
        '  "count": 1,\n'
        '  "reset": true\n'
        '}';

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No riders registered on backend',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Run bootstrap to register a rider and seed demo tasks:',
              style: TextStyle(color: Color(0xFF444444)),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              'POST /demo/bootstrap',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 6),
            const SelectableText(
              bootstrapUrl,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              sampleBody,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadRegisteredRiders,
              child: const Text('Refresh riders'),
            ),
          ],
        ),
      ),
    );
  }

  String _labelFromRiderId(String riderId) {
    final cleaned = riderId.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return riderId;

    final words = cleaned.split(' ');
    final titleCased = words
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
    return titleCased;
  }
}

class _RiderTile extends StatelessWidget {
  final String id;
  final String name;
  final String zone;
  final bool registered;
  final bool selected;
  final VoidCallback onTap;

  const _RiderTile({
    required this.id,
    required this.name,
    required this.zone,
    required this.registered,
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
              backgroundColor:
                  selected ? Colors.white24 : const Color(0xFFDDDDDD),
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
                    registered
                        ? '$zone · registered'
                        : '$zone · creates test rider',
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
