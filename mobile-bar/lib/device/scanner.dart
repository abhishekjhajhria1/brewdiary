// The camera, only while scanning: a guest card, a customer's shopping list, a product's
// barcode. Nothing is photographed or kept — the first code read is handed back and the
// camera closes.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/theme.dart';
import '../ui/widgets/common.dart';

/// Opens the camera and returns the first code [accept] takes (any code when null), or
/// null when closed. [reject] is said when a code is read that [accept] turns down.
Future<String?> scanCode(BuildContext context, {required String title, String? hint, bool Function(String raw)? accept, String reject = 'That isn\'t one of ours — try again.'}) =>
    Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScanScreen(title: title, hint: hint, accept: accept, reject: reject)));

class ScanScreen extends StatefulWidget {
  final String title;
  final String? hint;
  final bool Function(String raw)? accept;
  final String reject;
  const ScanScreen({super.key, required this.title, this.hint, this.accept, required this.reject});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _c = MobileScannerController(formats: const [BarcodeFormat.qrCode, BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.code128]);
  bool _done = false;
  String? _said;
  String? _lastRejected;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (widget.accept == null || widget.accept!(raw)) {
        _done = true;
        Haptics.success();
        Navigator.of(context).pop(raw);
        return;
      }
      if (raw != _lastRejected) {
        _lastRejected = raw;
        Haptics.error();
        setState(() => _said = widget.reject);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _c,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(S.xl),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'The camera is off for brewdiary bar. Allow it in your phone\'s Settings › Apps › brewdiary bar › Permissions, then try again.'
                    : 'The camera didn\'t start (${error.errorCode.name}). Close this and try again.',
                textAlign: TextAlign.center,
                style: T.sans(bd, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
        // The window to aim at.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: bd.accent, width: 2.5)),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(S.m),
            child: Column(children: [
              Row(children: [
                IconBtn(Ph.x, tooltip: 'Close', color: Colors.white, onTap: () => Navigator.of(context).pop()),
                Expanded(child: Text(widget.title, textAlign: TextAlign.center, style: T.sans(bd, size: 17, weight: FontWeight.w600, color: Colors.white))),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _c,
                  builder: (context, st, _) => IconBtn(
                    st.torchState == TorchState.on ? Ph.lightning : Ph.flashlight,
                    tooltip: st.torchState == TorchState.on ? 'Light off' : 'Light on',
                    color: Colors.white,
                    onTap: st.torchState == TorchState.unavailable ? null : () => _c.toggleTorch(),
                  ),
                ),
              ]),
              const Spacer(),
              if (_said != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.s),
                  child: Text(_said!, textAlign: TextAlign.center, style: T.sans(bd, size: 15, weight: FontWeight.w600, color: bd.accent)),
                ),
              if (widget.hint != null) Text(widget.hint!, textAlign: TextAlign.center, style: T.sans(bd, size: 15, color: Colors.white.withValues(alpha: .85))),
              const SizedBox(height: S.l),
            ]),
          ),
        ),
      ]),
    );
  }
}
