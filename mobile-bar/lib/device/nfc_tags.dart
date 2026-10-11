// Writing a table's (or a pickup point's) link onto an NFC sticker, from the phone in
// your hand: hold the sticker to the back of the phone, done. Any NTAG213/215/216
// sticker works. Locking it afterwards (recommended, and the default) means nobody can
// later rewrite the table's tag to point somewhere else; a new code means a new sticker.
import 'dart:async';
import 'dart:typed_data';

import 'package:brewdiary_core/links.dart' show ndefUriPayload;
import 'package:flutter/material.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

import '../ui/theme.dart';
import '../ui/widgets/common.dart';

/// The one NDEF message a brewdiary tag holds: a URI record for [url].
NdefMessage linkMessage(String url) => NdefMessage(records: [
      NdefRecord(typeNameFormat: TypeNameFormat.wellKnown, type: Uint8List.fromList(const [0x55]), identifier: Uint8List(0), payload: Uint8List.fromList(ndefUriPayload(url))),
    ]);

/// Opens the "hold the sticker to your phone" sheet and writes [url] when one arrives.
Future<void> writeTagSheet(BuildContext context, {required String url, required String what}) async {
  final NfcAvailability a;
  try {
    a = await NfcManager.instance.checkAvailability();
  } catch (_) {
    if (context.mounted) toast(context, 'This phone can\'t write NFC tags. Print the QR instead — it opens the same link.');
    return;
  }
  if (!context.mounted) return;
  if (a == NfcAvailability.unsupported) return toast(context, 'This phone has no NFC. Print the QR instead — it opens the same link.');
  if (a == NfcAvailability.disabled) return toast(context, 'NFC is off — turn it on in your phone\'s settings, then try again.');
  await showBdSheet<void>(context, title: 'Write $what\'s tag', builder: (_) => _WriteTag(url: url));
}

class _WriteTag extends StatefulWidget {
  final String url;
  const _WriteTag({required this.url});
  @override
  State<_WriteTag> createState() => _WriteTagState();
}

class _WriteTagState extends State<_WriteTag> {
  bool _lock = true;
  bool _listening = false;
  bool _written = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    if (_listening) unawaited(NfcManager.instance.stopSession().catchError((_) {}));
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _listening = true;
      _problem = null;
      _written = false;
    });
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        alertMessageIos: 'Hold the sticker to the top of your iPhone.',
        onDiscovered: _write,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          _problem = 'NFC didn\'t start — try again.';
        });
      }
    }
  }

  Future<void> _write(NfcTag tag) async {
    String? problem;
    final ndef = Ndef.from(tag);
    final message = linkMessage(widget.url);
    if (ndef == null) {
      problem = 'That tag can\'t hold a link. Use an NTAG213, 215 or 216 sticker.';
    } else if (!ndef.isWritable) {
      problem = 'That tag is locked. Use a fresh sticker.';
    } else if (ndef.maxSize < message.byteLength) {
      problem = 'That tag is too small for the link. Use an NTAG213 or bigger.';
    } else {
      try {
        await ndef.write(message: message);
        if (_lock) await ndef.writeLock();
      } catch (_) {
        problem = 'The sticker moved away before it was written — hold it still and try again.';
      }
    }
    await NfcManager.instance.stopSession(alertMessageIos: problem == null ? 'Written.' : null, errorMessageIos: problem).catchError((_) {});
    if (!mounted) return;
    problem == null ? Haptics.success() : Haptics.error();
    setState(() {
      _listening = false;
      _written = problem == null;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Pulse(
          active: _listening,
          color: bd.accent,
          radius: 60,
          times: 1000,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bd.accent.withValues(alpha: .14), border: Border.all(color: bd.accent.withValues(alpha: .6))),
            child: Icon(_written ? Ph.checkCircle : Ph.handTap, size: 44, color: bd.accentText),
          ),
        ),
      ),
      const SizedBox(height: S.l),
      Text(
        _written
            ? (_lock ? 'Written and locked. Tap it with any phone to check.' : 'Written. Tap it with any phone to check.')
            : (_problem ?? 'Hold the sticker flat against the back of your phone.'),
        textAlign: TextAlign.center,
        style: T.sans(bd, size: 16, weight: FontWeight.w600, color: _problem != null ? bd.tone(Tone.late) : bd.ink),
      ),
      const SizedBox(height: S.s),
      SelectableText(widget.url, textAlign: TextAlign.center, style: T.caption(bd)),
      const SizedBox(height: S.l),
      SettingRow(
        title: 'Lock the sticker',
        hint: 'Nobody can rewrite it to point somewhere else. A new code means a new sticker.',
        trailing: BdToggle(on: _lock, label: 'Lock the sticker', onChanged: (x) => setState(() => _lock = x)),
      ),
      const SizedBox(height: S.m),
      if (!_listening) BdButton(_written ? 'Write another' : 'Try again', icon: Ph.handTap, onTap: _start),
    ]);
  }
}
