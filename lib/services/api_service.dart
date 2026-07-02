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

  Future<List<String>> getRegisteredRiders() async {
    final res = await http.get(Uri.parse('$baseUrl/demo/riders'));
    _checkResponse(res, 'getRegisteredRiders');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final riders = body['registeredRiders'] as List<dynamic>? ?? const [];
    return riders.map((r) => r.toString()).toList();
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
    await submitProofResult(proof);
    return true;
  }

  /// Submits a signed proof and returns the issued Proof Certificate metadata.
  /// The delivery screen uses this to show the tamper-evident chain result.
  Future<ProofSubmissionResult> submitProofResult(
    SignedDeliveryProof proof,
  ) async {
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

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return ProofSubmissionResult.fromJson(body);
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'] as String? ?? 'UNKNOWN';
      throw ApiException(error, body['message'] as String? ?? 'Unknown error');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw const ApiException('NETWORK_ERROR', 'Unable to reach the demo API');
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

class ProofSubmissionResult {
  final String proofId;
  final String taskId;
  final String chainHash;
  final int chainPosition;
  final bool offlineSubmitted;
  final String issuedAt;

  const ProofSubmissionResult({
    required this.proofId,
    required this.taskId,
    required this.chainHash,
    required this.chainPosition,
    required this.offlineSubmitted,
    required this.issuedAt,
  });

  factory ProofSubmissionResult.fromJson(Map<String, dynamic> json) {
    return ProofSubmissionResult(
      proofId: json['proofId'] as String,
      taskId: json['taskId'] as String,
      chainHash: json['chainHash'] as String,
      chainPosition: json['chainPosition'] as int,
      offlineSubmitted: json['offlineSubmitted'] as bool? ?? false,
      issuedAt: json['issuedAt'] as String,
    );
  }
}

class ApiException implements Exception {
  final String code;
  final String message;

  const ApiException(this.code, this.message);

  @override
  String toString() => 'ApiException[$code]: $message';
}
