// ─────────────────────────────────────────────────────────────────────────────
// PODCHAIN Demo App — Delivery Screen
//
// The primary protocol interaction screen. Handles:
//   Tier 1 — Retrieves passive token and signs immediately
//   Tier 2 — Manual OTP entry or QR code scan, then signs
//   Tier 3 — Waits for recipient WebCrypto confirmation, then signs
//
// This is where payload construction, ECDSA signing, and proof submission
// (or offline queuing) all occur via the podchain_flutter library.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:podchain_flutter/podchain_flutter.dart';
import '../main.dart';
import '../services/api_service.dart';

enum _DeliveryState {
  idle,
  locating,
  waitingRecipient,
  signing,
  submitting,
  success,
  failed,
  offline
}

class DeliveryScreen extends StatefulWidget {
  final Map<String, dynamic> task;

  const DeliveryScreen({super.key, required this.task});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  _DeliveryState _state = _DeliveryState.idle;
  String? _recipientProof;
  String? _demoOtp;
  String? _demoQrPayload;
  String? _tier3DeepLink;
  String? _errorMessage;
  String? _proofId;
  String? _chainHash;
  int? _chainPosition;
  String? _otpValidationMessage;

  final _otpController = TextEditingController();
  bool _showQrScanner = false;

  int get _tier => widget.task['tier'] as int? ?? 1;
  String get _taskId => widget.task['taskId'] as String;

  @override
  void initState() {
    super.initState();
    _otpController.addListener(_onOtpChanged);
    if (_tier == 2) {
      _loadTier2DemoOtp();
    } else if (_tier == 3) {
      _loadTier3DeepLink();
    }
  }

  @override
  void dispose() {
    _otpController.removeListener(_onOtpChanged);
    _otpController.dispose();
    super.dispose();
  }

  // ── Token Collection ────────────────────────────────────────────────────────

  Future<void> _collectTier1Token() async {
    final apiService = context.read<ApiService>();
    final tokenData = await apiService.getTaskToken(_taskId);
    setState(() {
      _recipientProof = tokenData['token'] as String?;
    });
  }

  void _submitOtp() {
    final code = _otpController.text.trim();
    if (code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() {
        _recipientProof = code;
        _otpValidationMessage = null;
      });
      return;
    }

    setState(() {
      _recipientProof = null;
      _otpValidationMessage = 'Enter a valid 6-digit code.';
    });
  }

  void _onOtpChanged() {
    if (_tier != 2) return;

    final code = _otpController.text.trim();
    final isValid = code.length == 6 && RegExp(r'^\d{6}$').hasMatch(code);
    final nextProof = isValid ? code : null;
    final nextMessage =
        code.isEmpty || isValid ? null : 'Code must be exactly 6 digits.';

    if (nextProof == _recipientProof && nextMessage == _otpValidationMessage) {
      return;
    }

    setState(() {
      _recipientProof = nextProof;
      _otpValidationMessage = nextMessage;
    });
  }

  Future<void> _loadTier2DemoOtp() async {
    try {
      final apiService = context.read<ApiService>();
      final tokenData = await apiService.getTaskToken(_taskId);
      final otp = tokenData['otp'] as String?;
      final qrPayload = tokenData['qrPayload'] as String? ?? otp;
      if (!mounted || otp == null || otp.isEmpty) return;

      setState(() {
        _demoOtp = otp;
        _demoQrPayload = qrPayload;
        if (_otpController.text.isEmpty) {
          _otpController.text = otp;
        }
      });
    } catch (_) {
      // Demo hint fetch is best-effort only.
    }
  }

  Future<void> _loadTier3DeepLink() async {
    try {
      final apiService = context.read<ApiService>();
      final tokenData = await apiService.getTaskToken(_taskId);
      final deepLink = tokenData['deepLink'] as String?;
      if (!mounted || deepLink == null || deepLink.isEmpty) return;

      setState(() {
        _tier3DeepLink = deepLink;
      });
    } catch (_) {
      // The polling endpoint will surface a useful error when the rider checks.
    }
  }

  /// Polls the API until the recipient has completed Tier 3 confirmation.
  /// In production this would be a webhook; for the demo, we poll every 3s.
  Future<void> _pollForTier3Confirmation() async {
    final apiService = context.read<ApiService>();

    final immediate = await apiService.getTaskToken(_taskId);
    if (immediate['status'] == 'confirmed') {
      setState(() {
        _recipientProof = immediate['confirmationJson'] as String?;
        _errorMessage = null;
      });
      return;
    }

    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(seconds: 3));
      final tokenData = await apiService.getTaskToken(_taskId);
      if (tokenData['status'] == 'confirmed') {
        setState(() {
          _recipientProof = tokenData['confirmationJson'] as String?;
          _errorMessage = null;
        });
        return;
      }
    }

    setState(() {
      _errorMessage = 'Recipient has not completed confirmation. '
          'Check they have opened the link and tapped confirm.';
    });
  }

  // ── Signing and Submission ──────────────────────────────────────────────────

  Future<void> _signAndSubmit() async {
    if (_tier == 1 && _recipientProof == null) {
      setState(() {
        _state = _DeliveryState.submitting;
        _errorMessage = null;
      });
      try {
        await _collectTier1Token();
      } catch (e) {
        setState(() {
          _state = _DeliveryState.failed;
          _errorMessage = 'Unable to retrieve passive token: $e';
        });
        return;
      }
    }

    if (_recipientProof == null) return;

    if (!mounted) return;

    final podchain = context.read<AppState>().podchain!;
    final apiService = context.read<ApiService>();

    // Get GPS coordinates
    setState(() {
      _state = _DeliveryState.locating;
      _errorMessage = null;
    });

    DeliveryCoordinates coordinates;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      coordinates = DeliveryCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // GPS unavailable — use a placeholder for demo purposes
      // In production, GPS failure handling policy should be defined
      coordinates = const DeliveryCoordinates(latitude: 0.0, longitude: 0.0);
    }

    setState(() {
      _state = _DeliveryState.signing;
    });

    try {
      setState(() {
        _state = _DeliveryState.submitting;
      });

      final proof = await podchain.signDelivery(
        taskId: _taskId,
        recipientProof: _recipientProof!,
        coordinates: coordinates,
      );

      final result = await apiService.submitProofResult(proof);

      setState(() {
        _state = _DeliveryState.success;
        _proofId = result.proofId;
        _chainHash = result.chainHash;
        _chainPosition = result.chainPosition;
      });
      return;
    } on ApiException catch (e) {
      if (_isNetworkError(e)) {
        // Go offline — sign and queue
        await _signAndQueue(coordinates);
      } else {
        setState(() {
          _state = _DeliveryState.failed;
          _errorMessage = '${e.code}: ${e.message}';
        });
      }
    } on PodChainFlutterError catch (e) {
      setState(() {
        _state = _DeliveryState.failed;
        _errorMessage = '${e.code}: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _state = _DeliveryState.failed;
        _errorMessage = 'Unexpected error: $e';
      });
    }
  }

  bool _isNetworkError(ApiException error) {
    return error.code == 'NETWORK_ERROR' ||
        error.message.toLowerCase().contains('unable to reach');
  }

  Future<void> _signAndQueue(DeliveryCoordinates coordinates) async {
    final podchain = context.read<AppState>().podchain!;

    try {
      await podchain.signAndQueue(
        taskId: _taskId,
        recipientProof: _recipientProof!,
        coordinates: coordinates,
      );
      setState(() {
        _state = _DeliveryState.offline;
      });
    } catch (e) {
      setState(() {
        _state = _DeliveryState.failed;
        _errorMessage = 'Signing failed: ${e.toString()}';
      });
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Delivery'),
        leading:
            _state == _DeliveryState.success || _state == _DeliveryState.offline
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTaskSummary(),
              const SizedBox(height: 24),
              Expanded(child: _buildMainContent()),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskSummary() {
    final tier = _tier;
    final tierLabel =
        ['', 'Passive Token', 'OTP Confirmation', 'Two-Sided Signing'][tier];
    final tierColor =
        [Colors.grey, Colors.blue, Colors.orange, Colors.green][tier];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.task['recipientName'] as String? ?? 'Recipient',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(
                      color: tierColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.task['deliveryAddress'] as String? ?? '',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_state) {
      case _DeliveryState.success:
        return _buildSuccessView();
      case _DeliveryState.offline:
        return _buildOfflineView();
      case _DeliveryState.failed:
        return _buildErrorView();
      case _DeliveryState.locating:
      case _DeliveryState.waitingRecipient:
      case _DeliveryState.signing:
      case _DeliveryState.submitting:
        return _buildLoadingView();
      default:
        return _buildInputView();
    }
  }

  Widget _buildInputView() {
    if (_showQrScanner) {
      return _buildQrScanner();
    }

    switch (_tier) {
      case 1:
        return _buildTier1View();
      case 2:
        return _buildTier2View();
      case 3:
        return _buildTier3View();
      default:
        return const SizedBox();
    }
  }

  // ── Tier-specific input views ────────────────────────────────────────────────

  Widget _buildTier1View() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepLabel(step: '1', label: 'Hand over the package'),
        SizedBox(height: 12),
        Text(
          'Verify the recipient\'s identity and hand over the package. '
          'No code is required — the platform token will be retrieved automatically.',
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        SizedBox(height: 24),
        _StepLabel(step: '2', label: 'Tap "Confirm Delivery"'),
        SizedBox(height: 12),
        Text(
          'The app will retrieve the delivery token and sign the proof with your key. '
          'Your GPS coordinates will be recorded at the moment of signing.',
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildTier2View() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(step: '1', label: 'Collect the confirmation code'),
        const SizedBox(height: 8),
        const Text(
          'Ask the recipient to show the confirmation code from their phone. '
          'You can either type it or scan the QR code displayed on their screen.',
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 20),

        // OTP entry
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: '6-digit code',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _submitOtp,
                  ),
                ),
                onSubmitted: (_) => _submitOtp(),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showQrScanner = true),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Scan QR'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
            ),
          ],
        ),

        if (_recipientProof != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF065F46), size: 16),
                SizedBox(width: 8),
                Text(
                  'Code accepted — ready to sign',
                  style: TextStyle(color: Color(0xFF065F46), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
        if (_otpValidationMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _otpValidationMessage!,
            style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12),
          ),
        ],
        if (_demoOtp != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFF3730A3), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Demo OTP: $_demoOtp',
                        style: const TextStyle(
                          color: Color(0xFF3730A3),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _otpController.text = _demoOtp!;
                        _submitOtp();
                      },
                      child: const Text('Use'),
                    ),
                  ],
                ),
                if (_demoQrPayload != null) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    'QR payload: $_demoQrPayload',
                    style: const TextStyle(
                      color: Color(0xFF3730A3),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTier3View() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepLabel(step: '1', label: 'Recipient confirms via link'),
        const SizedBox(height: 8),
        const Text(
          'The recipient has received a confirmation link. '
          'Ask them to open it and tap "I confirm receipt".',
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (_recipientProof == null) ...[
          OutlinedButton.icon(
            onPressed: () async {
              setState(() {
                _state = _DeliveryState.waitingRecipient;
                _errorMessage = null;
              });
              await _pollForTier3Confirmation();
              if (!mounted) return;
              if (_state == _DeliveryState.waitingRecipient) {
                setState(() {
                  _state = _DeliveryState.idle;
                });
              }
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Check confirmation status'),
          ),
          if (_tier3DeepLink != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recipient signing link',
                    style: TextStyle(
                      color: Color(0xFF3730A3),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _tier3DeepLink!,
                    style: const TextStyle(
                      color: Color(0xFF3730A3),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _tier3DeepLink!));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy link'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12),
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF065F46), size: 16),
                SizedBox(width: 8),
                Text(
                  'Recipient confirmed — ready to sign',
                  style: TextStyle(color: Color(0xFF065F46), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQrScanner() {
    return Column(
      children: [
        const Text(
          'Point camera at the recipient\'s QR code',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              onDetect: (capture) {
                final barcode = capture.barcodes.first;
                final proof = _extractTier2ProofFromQr(barcode.rawValue);
                if (proof != null) {
                  setState(() {
                    _recipientProof = proof;
                    _otpController.text = proof;
                    _otpValidationMessage = null;
                    _showQrScanner = false;
                  });
                } else if (barcode.rawValue != null) {
                  setState(() {
                    _otpValidationMessage =
                        'Scanned QR did not contain a valid 6-digit code.';
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _showQrScanner = false),
          child: const Text('Enter code manually instead'),
        ),
      ],
    );
  }

  // ── State views ──────────────────────────────────────────────────────────────

  Widget _buildLoadingView() {
    final messages = {
      _DeliveryState.locating: 'Getting GPS coordinates…',
      _DeliveryState.waitingRecipient:
          'Waiting for recipient browser signature…',
      _DeliveryState.signing: 'Signing delivery proof…',
      _DeliveryState.submitting: 'Submitting to platform…',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            messages[_state] ?? 'Please wait…',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle, color: Color(0xFF059669), size: 64),
        const SizedBox(height: 20),
        const Text(
          'Delivery Confirmed',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'A cryptographic Proof Certificate has been issued and stored.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        if (_chainHash != null) ...[
          const SizedBox(height: 20),
          _HashDisplay(label: 'Chain Hash', value: _chainHash!),
        ],
        if (_proofId != null) ...[
          const SizedBox(height: 10),
          _HashDisplay(label: 'Proof ID', value: _proofId!),
        ],
        if (_chainPosition != null) ...[
          const SizedBox(height: 10),
          Text(
            'Chain position $_chainPosition',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Task List'),
        ),
      ],
    );
  }

  Widget _buildOfflineView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.cloud_queue, color: Color(0xFF0369A1), size: 64),
        const SizedBox(height: 20),
        const Text(
          'Proof Queued Offline',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'The delivery proof was signed successfully and added to the offline queue. '
          'It will be submitted automatically when connectivity is restored.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Task List'),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 64),
        const SizedBox(height: 20),
        const Text(
          'Submission Failed',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, height: 1.5),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() {
            _state = _DeliveryState.idle;
            _errorMessage = null;
          }),
          child: const Text('Try Again'),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    if (_state == _DeliveryState.success ||
        _state == _DeliveryState.offline ||
        _state == _DeliveryState.failed ||
        _state == _DeliveryState.locating ||
        _state == _DeliveryState.waitingRecipient ||
        _state == _DeliveryState.signing ||
        _state == _DeliveryState.submitting) {
      return const SizedBox.shrink();
    }

    final ready = _tier == 1 || _recipientProof != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tier == 1 && _recipientProof == null)
          OutlinedButton(
            onPressed: _collectTier1Token,
            child: const Text('Retrieve Token'),
          ),
        if (_tier == 1 && _recipientProof == null) const SizedBox(height: 10),
        FilledButton(
          onPressed: ready ? _signAndSubmit : null,
          child: const Text('Confirm Delivery & Sign'),
        ),
      ],
    );
  }

  String? _extractTier2ProofFromQr(String? raw) {
    if (raw == null) return null;

    final trimmed = raw.trim();
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) return trimmed;

    final uri = Uri.tryParse(trimmed);
    final uriCode = uri?.queryParameters['otp'] ?? uri?.queryParameters['code'];
    if (uriCode != null && RegExp(r'^\d{6}$').hasMatch(uriCode)) {
      return uriCode;
    }

    return null;
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _StepLabel extends StatelessWidget {
  final String step;
  final String label;

  const _StepLabel({required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _HashDisplay extends StatelessWidget {
  final String label;
  final String value;

  const _HashDisplay({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
