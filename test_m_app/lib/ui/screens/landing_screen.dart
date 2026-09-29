// The guest home — a port of src/components/onboarding/Landing.tsx. A real, working
// month grid you can log into without an account (it lives on the device), the
// ledger of what the app does, and the sign-up/sign-in sheet. Plus the first-run
// age gate, which checks the legal age WHERE YOU ARE.
import 'package:flutter/material.dart';

import '../../config.dart';
import 'package:brewdiary_core/date.dart';
import 'package:brewdiary_core/derive.dart';
import 'package:brewdiary_core/jurisdiction.dart';
import '../../data/auth.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/moments.dart';
import '../widgets/mosaic.dart';
import '../widgets/page.dart';
import '../widgets/pickers.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  late int _y = appNow().year;
  late int _m = appNow().month - 1;
  bool _autoOpened = false;

  void _step(int delta) {
    final d = addMonths(DateTime(_y, _m + 1, 1), delta);
    setState(() {
      _y = d.year;
      _m = d.month - 1;
    });
  }

  Future<void> _open(String key) async {
    final added = await openLog(context, key, cheer: false);
    // After the first log, ask them to keep it — once, after the square has had its moment.
    if (!mounted || _autoOpened || entryStore.entries.isEmpty) return;
    _autoOpened = true;
    if (added) await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) showAuthSheet(context, signup: true);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final now = appNow();
    return ScrollPage(
      barTitle: const Wordmark(),
      actions: [
        TextAction('Sign in', accent: true, size: 15, onTap: () => showAuthSheet(context, signup: false)),
        ThemeDot(dark: ThemeStore.instance.isDark, onTap: ThemeStore.instance.toggle),
      ],
      children: [
        ListenableBuilder(
          listenable: entryStore,
          builder: (context, _) {
            final entries = entryStore.entries;
            final canNext = _y < now.year || (_y == now.year && _m < now.month - 1);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: S.l),
              Text('A DRINK DIARY', style: T.section(bd)),
              const SizedBox(height: S.m),
              Semantics(header: true, child: Text('Every night\ngets a square.', style: T.serif(bd, size: 46, height: 1.02))),
              const SizedBox(height: S.xl),
              Text('Coffee, wine, a midnight kombucha — whatever you poured. Tap a day, log it in a breath, and watch the year quietly fill in.', style: T.bodyMuted(bd)),
              const SizedBox(height: S.m),
              Text('The squares darken the more you drink, so a month of habits is one glance, not a spreadsheet. Keep it private, or pour with friends.', style: T.bodyMuted(bd)),
              const SizedBox(height: S.x3),
              const YearPreview(),
              const SectionHeader('Try it — tap a day'),
              MonthCalendar(
                year: _y,
                month: _m,
                counts: countsByDate(entries),
                dryKeys: dryDates(entries),
                onSelect: _open,
                onPrev: () => _step(-1),
                onNext: () => _step(1),
                canNext: canNext,
                beckonToday: entries.isEmpty,
              ),
              const SizedBox(height: S.m),
              Text(
                entries.isEmpty ? 'No account needed yet — it stays on this phone.' : 'Logged on this device. Make a diary and it comes with you.',
                textAlign: TextAlign.center,
                style: T.caption(bd),
              ),
              const SizedBox(height: 56),
              Text('One tap a night.\nIt adds up.', style: T.serif(bd, size: 34, height: 1.08)),
              const SizedBox(height: S.l),
              for (var i = 0; i < _ledger.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: S.l),
                  decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: bd.line, width: .8))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 36,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text((i + 1).toString().padLeft(2, '0'), style: T.sans(bd, size: 13, weight: FontWeight.w600, color: bd.faint).copyWith(fontFeatures: T.tnum)),
                      ),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_ledger[i].$1, style: T.serif(bd, size: 20, height: 1.2)),
                        const SizedBox(height: 6),
                        Text(_ledger[i].$2, style: T.bodyMuted(bd)),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: S.x3),
              Glass(
                padding: const EdgeInsets.all(S.xxl),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(entries.isNotEmpty ? 'Keep what you logged.' : 'Start tonight.', style: T.serif(bd, size: 30, height: 1.1)),
                  const SizedBox(height: S.m),
                  Text(
                    entries.isNotEmpty
                        ? 'Your entries live on this device until you make a diary. Sign up and they come with you — phone, laptop, next year.'
                        : 'A diary takes an email and a password. Free, no card, and the first square is one tap away.',
                    style: T.bodyMuted(bd),
                  ),
                  const SizedBox(height: S.xxl),
                  BdButton('Create a diary', onTap: () {
                    _autoOpened = true;
                    showAuthSheet(context, signup: true);
                  }),
                  const SizedBox(height: S.xs),
                  Center(child: TextAction('I already have one — sign in', onTap: () => showAuthSheet(context, signup: false))),
                ]),
              ),
              if (!Config.cloud) ...[
                const SizedBox(height: S.l),
                Text('Running without a cloud backend — "Create a diary" keeps everything on this phone.', textAlign: TextAlign.center, style: T.caption(bd)),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

const _ledger = [
  ('Streaks that survive a bad week', 'Log a night, keep the run. One missed day is forgiven, so a slip doesn’t wipe a month. Seven, thirty, a hundred — the meter fills as you go.'),
  ('Your year, counted', 'What you poured most, your longest run, the words you keep reaching for. All read back from your entries — nothing to fill in twice.'),
  ('Together, not a feed', 'Share a single pour with friends, a private circle, or the party you’re at. Cheers and comments, no audience to perform for.'),
  ('Settle the round', 'Add a tab, add who was there, and the split falls out. Who paid, who owes, done at the table.'),
  ('Ninkasi, behind the bar', 'Ask what to pour next. She reads your diary and your friends’ shared pours, not a catalogue of sponsored bottles.'),
  ('Private until you say otherwise', 'Every entry starts private on your device. Sharing is a separate tap, always after the fact.'),
];

/// Light/dark switch for the top bar — so the app is never stuck in one theme.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) {
        final dark = ThemeStore.instance.isDark;
        return IconBtn(dark ? Ph.sun : Ph.moon, tooltip: dark ? 'Switch to the light theme' : 'Switch to the dark theme', onTap: ThemeStore.instance.toggle);
      },
    );
  }
}

// ── the auth sheet ───────────────────────────────────────────────────────────
Future<void> showAuthSheet(BuildContext context, {required bool signup}) => showBdSheet(context, builder: (_) => _AuthSheet(signup: signup));

class _AuthSheet extends StatefulWidget {
  final bool signup;
  const _AuthSheet({required this.signup});
  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  late bool _signup = widget.signup;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  bool _confirm = false;
  bool _resetSent = false;
  // Email-code sign-in (cloud builds): no password, a 6-digit code instead.
  bool _useCode = false;
  bool _codeSent = false;
  final _code = TextEditingController();

  Future<void> _sendCode() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await auth.sendEmailCode(_email.text, create: _signup, name: _name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _codeSent = true;
      } else {
        _error = _signup ? res.error : "We couldn't send a code to that email. New here? Create a diary instead.";
      }
    });
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await auth.verifyEmailCode(_email.text, _code.text);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _error = res.error;
        _busy = false;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = _signup ? await auth.signUp(_email.text, _password.text, _name.text) : await auth.signIn(_email.text, _password.text);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _error = res.error;
        _busy = false;
      });
      return;
    }
    if (res.needsConfirm) {
      setState(() {
        _confirm = true;
        _busy = false;
      });
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _forgot() async {
    if (_email.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email above first, then tap reset.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await auth.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _resetSent = true;
      } else {
        _error = res.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    if (_confirm) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: S.s),
        Icon(Ph.envelopeSimple, size: 32, color: bd.accentText),
        const SizedBox(height: S.m),
        Text('Check your email.', style: T.title(bd)),
        const SizedBox(height: S.m),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'We sent a confirmation link to ', style: T.bodyMuted(bd)),
          TextSpan(text: _email.text.trim(), style: T.body(bd)),
          TextSpan(text: '. Tap it to finish, then come back and sign in.', style: T.bodyMuted(bd)),
        ])),
        const SizedBox(height: S.xxl),
        BdButton('Go to sign in', onTap: () => setState(() {
              _confirm = false;
              _signup = false;
            })),
      ]);
    }
    final n = entryStore.entries.length;
    final kicker = _signup ? (n > 0 ? (n > 1 ? '$n nights logged' : 'First night logged') : 'New diary') : 'Welcome back';
    final ready = _email.text.trim().isNotEmpty && _password.text.length >= 6;
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: S.xs),
        Text(kicker, style: T.sans(bd, size: 14, weight: FontWeight.w500, color: bd.accentText)),
        const SizedBox(height: S.s),
        Text(_signup ? 'Keep your diary.' : 'Sign in.', style: T.title(bd)),
        const SizedBox(height: S.s),
        Text(_signup ? "Save what you logged and start a streak. Email and a password — that's it." : 'Pick up where you left off.', style: T.bodyMuted(bd)),
        const SizedBox(height: S.xl),
        if (Config.cloud) ...[
          Segmented<bool>(
            options: const [(false, 'Password'), (true, 'Email me a code')],
            value: _useCode,
            onChanged: (v) => setState(() {
              _useCode = v;
              _codeSent = false;
              _error = null;
            }),
          ),
          const SizedBox(height: S.xl),
        ] else
          const SizedBox(height: S.s),
        if (_signup) ...[
          LineField(controller: _name, label: 'Name', hint: 'What should we call you?', caps: TextCapitalization.words, action: TextInputAction.next, autofill: const [AutofillHints.name], onChanged: (_) => setState(() {})),
          const SizedBox(height: S.xl),
        ],
        LineField(
          controller: _email,
          label: 'Email',
          hint: 'you@email.com',
          keyboard: TextInputType.emailAddress,
          caps: TextCapitalization.none,
          action: TextInputAction.next,
          autofill: const [AutofillHints.email],
          onChanged: (_) => setState(() {}),
        ),
        if (_useCode) ...[
          if (_codeSent) ...[
            const SizedBox(height: S.xl),
            LineField(
              controller: _code,
              label: 'Code',
              hint: 'The code from the email',
              keyboard: TextInputType.number,
              caps: TextCapitalization.none,
              action: TextInputAction.done,
              autofill: const [AutofillHints.oneTimeCode],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _code.text.trim().length >= 6 ? _verifyCode() : null,
            ),
            Padding(padding: const EdgeInsets.only(top: S.s), child: Text('Sent to ${_email.text.trim()}. It works for a few minutes.', style: T.caption(bd))),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: S.m), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
          const SizedBox(height: S.xxl),
          _codeSent
              ? BdButton(_signup ? 'Start my diary' : 'Sign in', busy: _busy, onTap: _code.text.trim().length >= 6 ? _verifyCode : null)
              : BdButton('Email me a code', busy: _busy, onTap: _email.text.trim().contains('@') ? _sendCode : null),
          if (_codeSent) Center(child: TextAction('Send a new code', onTap: _busy ? null : _sendCode)),
        ] else ...[
        const SizedBox(height: S.xl),
        Stack(alignment: Alignment.bottomRight, children: [
          LineField(
            controller: _password,
            label: 'Password',
            hint: _signup ? 'At least 6 characters' : 'Your password',
            obscure: !_showPassword,
            caps: TextCapitalization.none,
            action: TextInputAction.done,
            autofill: [_signup ? AutofillHints.newPassword : AutofillHints.password],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => ready ? _submit() : null,
          ),
          IconBtn(_showPassword ? Ph.eyeSlash : Ph.eye, size: 20, color: bd.faint, tooltip: _showPassword ? 'Hide password' : 'Show password', onTap: () => setState(() => _showPassword = !_showPassword)),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: S.m), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
        const SizedBox(height: S.xxl),
        BdButton(_signup ? 'Start my diary' : 'Sign in', busy: _busy, onTap: ready ? _submit : null),
        ],
        const SizedBox(height: S.xs),
        if (!_signup && !_useCode)
          Center(
            child: _resetSent
                ? Padding(padding: const EdgeInsets.symmetric(vertical: S.m), child: Text('Reset link sent to ${_email.text.trim()} — check your inbox.', textAlign: TextAlign.center, style: T.caption(bd)))
                : TextAction('Forgot password?', onTap: _busy ? null : _forgot),
          ),
        Center(
          child: TextAction(_signup ? 'Already have a diary? Sign in' : 'New here? Create a diary', accent: true, onTap: () => setState(() {
                _error = null;
                _signup = !_signup;
              })),
        ),
      ]),
    );
  }
}

// ── the age gate ─────────────────────────────────────────────────────────────
/// A first-run age check where you ARE (the legal age differs by country). We check
/// the date, then keep only a yes and the cleared bar — never the date of birth.
class AgeGateScreen extends StatefulWidget {
  const AgeGateScreen({super.key});
  @override
  State<AgeGateScreen> createState() => _AgeGateScreenState();
}

class _AgeGateScreenState extends State<AgeGateScreen> {
  String _country = 'IN';
  DateTime? _dob;
  bool _blocked = false;
  String? _error;

  Future<void> _pickCountry() async {
    final c = await pickCountry(context, current: _country);
    if (c != null) setState(() => _country = c);
  }

  Future<void> _pickDob() async {
    final now = appNow();
    final d = await pickDate(
      context,
      title: 'Date of birth',
      initial: _dob ?? DateTime(now.year - 25, now.month, now.day),
      first: DateTime(now.year - 110),
      last: now,
    );
    if (d != null) {
      setState(() {
        _dob = d;
        _error = null;
      });
    }
  }

  void _enter() {
    if (_dob == null) {
      setState(() => _error = 'Please choose your date of birth.');
      return;
    }
    if (!PlaceStore.instance.confirmAge(_dob!, _country == 'ZZ' ? null : _country)) setState(() => _blocked = true);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final mq = MediaQuery.of(context);
    final required = PlaceStore.instance.legalAgeFor(_country == 'ZZ' ? null : _country);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(S.gutter, mq.padding.top + S.xl, S.gutter, mq.padding.bottom + S.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Glass(
            strong: true,
            blur: true,
            radius: rSheet,
            padding: const EdgeInsets.fromLTRB(S.xxl, S.x3, S.xxl, S.xxl),
            child: AnimatedSize(
              duration: Motion.med,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Wordmark(size: 22),
                const SizedBox(height: S.xl),
                if (_blocked) ...[
                  Text('Not just yet.', style: T.title(bd)),
                  const SizedBox(height: S.m),
                  Text('You need to be of legal drinking age where you are ($required+) to use brewdiary. Come back when you are.', style: T.bodyMuted(bd)),
                  const SizedBox(height: S.xxl),
                  BdButton('Re-enter my date of birth', kind: BtnKind.secondary, onTap: () => setState(() => _blocked = false)),
                ] else ...[
                  Text('A quick check.', style: T.title(bd)),
                  const SizedBox(height: S.m),
                  Text('brewdiary is a diary of what you drink — alcohol included. Confirm your date of birth to come in.', style: T.bodyMuted(bd)),
                  const SizedBox(height: S.xxl),
                  PickerField(label: 'Where you are', value: _country == 'ZZ' ? 'Somewhere else' : countryLabel(_country), onTap: _pickCountry),
                  const SizedBox(height: S.s),
                  Text("The legal drinking age differs by country — here it's $required+.", style: T.caption(bd)),
                  const SizedBox(height: S.xl),
                  PickerField(
                    label: 'Date of birth',
                    value: _dob == null ? 'Choose a date' : writtenDate(_dob!),
                    placeholder: _dob == null,
                    icon: Ph.calendarBlank,
                    onTap: _pickDob,
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
                  const SizedBox(height: S.xxl),
                  BdButton('Enter', onTap: _enter),
                  const SizedBox(height: S.l),
                  Text("Please drink responsibly. Your date of birth isn't sent anywhere or saved — we check it, then keep only a yes on this device.", style: T.caption(bd)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
