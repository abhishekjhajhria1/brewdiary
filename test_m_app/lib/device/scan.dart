// Opening a place from its code, inside the app: the camera reads a table's or a
// counter's QR, or the phone reads its NFC tag. (Most phones also open the tag or the QR
// on their own — this is for when they don't.) Only brewdiary links are followed; a guest
// card or a shopping list is for the staff's scanner, and says so.
import 'dart:async';

import 'package:brewdiary_core/links.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';

/// Follow a scanned code: a table, a menu, a party invite open in the app; the ready
/// board in the browser. False when it isn't something a guest opens.
bool openScanned(BuildContext context, String raw) {
  final s = classifyScan(raw);
  switch (s.kind) {
    case ScanKind.table:
    case ScanKind.menu:
      Shell.openLink(Uri.parse(raw.trim()));
      return true;
    case ScanKind.ready:
      launchUrl(Uri.parse(raw.trim()), mode: LaunchMode.externalApplication);
      return true;
    case ScanKind.guestCard:
    case ScanKind.shopList:
      toast(context, 'That code is for the staff\'s scanner — show it at the counter.');
      return false;
    case ScanKind.unknown:
      final uri = Uri.tryParse(raw.trim());
      // Our other links (an invite, a profile, a party) route the same way.
      if (uri != null && (uri.host == 'bwdy.site' || uri.host.endsWith('.bwdy.site'))) {
        Shell.openLink(uri);
        return true;
      }
      return false;
  }
}

/// The camera, until it reads a brewdiary code — then that place opens.
Future<void> scanToOpen(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScanScreen()));
  if (raw != null && context.mounted) openScanned(context, raw);
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();
  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  final _c = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _said;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _ours(String raw) {
    final k = classifyScan(raw).kind;
    if (k != ScanKind.unknown) return true;
    final uri = Uri.tryParse(raw.trim());
    return uri != null && uri.scheme == 'https' && (uri.host == 'bwdy.site' || uri.host.endsWith('.bwdy.site'));
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      if (_ours(raw)) {
        _done = true;
        Haptics.success();
        Navigator.of(context).pop(raw);
        return;
      }
      if (_said == null) setState(() => _said = 'That isn\'t a brewdiary code. Look for the one on the table or the counter.');
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
                    ? 'The camera is off for brewdiary. Allow it in your phone\'s Settings, then try again — or use your phone\'s own camera app.'
                    : 'The camera didn\'t start. Close this and try again.',
                textAlign: TextAlign.center,
                style: T.body(bd, color: Colors.white),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(width: 240, height: 240, decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: bd.accent, width: 2.5))),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(S.m),
            child: Column(children: [
              Row(children: [
                IconBtn(Ph.x, tooltip: 'Close', color: Colors.white, onTap: () => Navigator.of(context).pop()),
                Expanded(child: Text('Scan the code', textAlign: TextAlign.center, style: T.row(bd, color: Colors.white))),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _c,
                  builder: (context, st, _) => IconBtn(
                    Ph.flashlight,
                    tooltip: st.torchState == TorchState.on ? 'Light off' : 'Light on',
                    color: st.torchState == TorchState.on ? bd.accent : Colors.white,
                    onTap: st.torchState == TorchState.unavailable ? null : () => _c.toggleTorch(),
                  ),
                ),
              ]),
              const Spacer(),
              if (_said != null) Padding(padding: const EdgeInsets.only(bottom: S.s), child: Text(_said!, textAlign: TextAlign.center, style: T.body(bd, color: bd.accent))),
              Text('The QR on the table or the counter. It opens the menu here — the place learns nothing about you.', textAlign: TextAlign.center, style: T.body(bd, color: Colors.white.withValues(alpha: .85))),
              const SizedBox(height: S.l),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The link on an NFC tag ("U" record), or null.
String? linkOnTag(NdefMessage? m) {
  for (final r in m?.records ?? const <NdefRecord>[]) {
    if (r.typeNameFormat == TypeNameFormat.wellKnown && r.type.length == 1 && r.type.first == 0x55) {
      final u = uriFromNdefPayload(r.payload);
      if (u != null) return u;
    }
  }
  return null;
}

/// "Hold your phone to the tag": reads one tag and opens what it holds.
Future<void> readTagToOpen(BuildContext context) async {
  NfcAvailability a;
  try {
    a = await NfcManager.instance.checkAvailability();
  } catch (_) {
    a = NfcAvailability.unsupported;
  }
  if (!context.mounted) return;
  if (a == NfcAvailability.unsupported) return toast(context, 'This phone has no NFC — scan the QR instead.');
  if (a == NfcAvailability.disabled) return toast(context, 'NFC is off — turn it on in your phone\'s settings, or scan the QR.');
  final link = await showBdSheet<String>(context, title: 'Tap the tag', builder: (_) => const _ReadTag());
  if (link != null && context.mounted && !openScanned(context, link)) toast(context, 'That tag isn\'t a brewdiary one.');
}

class _ReadTag extends StatefulWidget {
  const _ReadTag();
  @override
  State<_ReadTag> createState() => _ReadTagState();
}

class _ReadTagState extends State<_ReadTag> {
  String? _problem;

  @override
  void initState() {
    super.initState();
    NfcManager.instance
        .startSession(
          pollingOptions: const {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
          alertMessageIos: 'Hold the top of your iPhone near the tag.',
          onDiscovered: (tag) async {
            final ndef = Ndef.from(tag);
            final link = linkOnTag(ndef?.cachedMessage ?? await ndef?.read());
            await NfcManager.instance.stopSession(alertMessageIos: link == null ? null : 'Opening…', errorMessageIos: link == null ? 'Nothing to open on that tag.' : null).catchError((_) {});
            if (!mounted) return;
            if (link == null) {
              Haptics.error();
              setState(() => _problem = 'Nothing to open on that tag. Try the QR.');
            } else {
              Haptics.success();
              Navigator.of(context).pop(link);
            }
          },
        )
        .catchError((_) {
      if (mounted) setState(() => _problem = 'NFC didn\'t start — try the QR.');
    });
  }

  @override
  void dispose() {
    unawaited(NfcManager.instance.stopSession().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Pulse(
          active: _problem == null,
          color: bd.accent,
          radius: 60,
          times: 1000,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .14), border: Border.all(color: bd.accent.withValues(alpha: .6))),
            child: Icon(Ph.contactlessPayment, size: 44, color: bd.accentText),
          ),
        ),
      ),
      const SizedBox(height: S.l),
      Text(_problem ?? 'Hold the top of your phone near the brewdiary sticker.', textAlign: TextAlign.center, style: T.row(bd)),
      const SizedBox(height: S.l),
    ]);
  }
}
