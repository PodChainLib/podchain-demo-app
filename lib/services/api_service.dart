// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Demo App — API Service
// All communication with the podchain-demo-api backend.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:podchain_flutter/podchain_flutter.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  // ── Rider Registration ──────────────────────────────────────────────────────

  Future<void> registerKey({
    required String riderId,
    required Map<String, dynamic> publicKey,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/riders/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'riderId': riderId, 'publicKey': publicKey}),
    );
    _checkResponse(res, 'registerKey');
  }

  // ── Task Management ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTasks(String riderId) async {
    final res = await http.get(Uri.parse('$baseUrl/tasks?riderId=$riderId'));
    _checkResponse(res, 'getTasks');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(body['tasks'] as List);
  }

  Future<Map<String, dynamic>> getTaskToken(String taskId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/tasks/$taskId/recipient-token'),
    );
    _checkResponse(res, 'getTaskToken');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Proof Submission ────────────────────────────────────────────────────────

  /// Submits a signed proof to the platform API.
  /// Returns true on success, false on API-level rejection.
  /// This method is also used as the [SubmitProofCallback] for the offline queue.
  Future<bool> submitProof(SignedDeliveryProof proof) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/tasks/${proof.taskId}/complete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'riderId': proof.riderId,
          'payload': proof.payload,
          'signature': proof.signature,
        }),
      );

      if (res.statusCode == 200) return true;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'] as String? ?? 'UNKNOWN';
      throw ApiException(error, body['message'] as String? ?? 'Unknown error');
    } catch (e) {
      if (e is ApiException) rethrow;
      return false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _checkResponse(http.Response res, String operation) {
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(
        body['error'] as String? ?? 'UNKNOWN',
        body['message'] as String? ?? 'Request failed: $operation',
      );
    }
  }
}

class ApiException implements Exception {
  final String code;
  final String message;

  const ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException[$code]: $message';
}
