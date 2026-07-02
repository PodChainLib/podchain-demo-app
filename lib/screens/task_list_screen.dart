// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Demo App — Task List Screen
// Displays the rider's pending delivery tasks fetched from the demo API.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'delivery_screen.dart';
import 'login_screen.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final riderId = context.read<AppState>().riderId!;
      final apiService = context.read<ApiService>();
      final tasks = await apiService.getTasks(riderId);
      setState(() {
        _tasks = tasks;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
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
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Deliveries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(
              appState.riderId ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
            tooltip: 'Refresh tasks',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              appState.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadTasks, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No pending deliveries', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _TaskCard(
          task: _tasks[index],
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: context.read<AppState>(),
                  child: DeliveryScreen(task: _tasks[index]),
                ),
              ),
            );
            _loadTasks(); // Refresh after returning from delivery screen
          },
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;

  const _TaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tier = task['tier'] as int? ?? 1;
    final tierLabel = ['', 'Passive', 'OTP', '2-Sided'][tier];
    final tierColor =
        [Colors.grey, Colors.blue, Colors.orange, Colors.green][tier];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task['recipientName'] as String? ?? 'Recipient',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tierColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Tier $tier · $tierLabel',
                    style: TextStyle(
                      color: tierColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task['deliveryAddress'] as String? ?? '',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  task['recipientPhone'] as String? ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Task: ${(task['taskId'] as String? ?? '').substring(0, 8)}…',
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.grey),
                ),
                const Row(
                  children: [
                    Text('Deliver',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
