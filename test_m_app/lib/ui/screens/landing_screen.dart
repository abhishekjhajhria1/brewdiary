// The guest home — a port of src/components/onboarding/Landing.tsx. A real, working
// month grid you can log into without an account (it lives on the device), the
// ledger of what the app does, and the sign-up/sign-in sheet.
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../core/date.dart';
import '../../core/derive.dart';
import '../../data/auth.dart';
import '../../data/entries.dart';
import '../../data/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/log_sheet.dart';
import '../widgets/mosaic.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  late int _y = DateTime.now().year;
  late int _m = DateTime.now().month - 1;
  bool _autoOpened = false;

  void _step(int delta) {
    final d = addMonths(DateTime(_y, _m + 1, 1), delta);
    setState(() {
      _y = d.year;
      _m = d.month - 1;
    });
  }

  Future<void> _open(String key) async {
    final entries = entryStore.entries;
    await showLogSheet(context, dateKey: key, recentDrinks: recentDrinks(entries), recentMoods: recentMoods(entries));
    // After the first log, ask them to keep it — once.
    if (!mounted || _autoOpened || entryStore.entries.isEmpty) return;
    _autoOpened = true;
    showAuthSheet(context, signup: true);
  }

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final now = DateTime.now();
    return ListenableBuilder(
      listenable: entryStore,
      builder: (context, _) {
        final entries = entryStore.entries;
        final canNext = _y < now.year || (_y == now.year && _m < now.month - 1);
        return ListView(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 40),
          children: [
            Row(children: [
              Text('brewdiary', style: T.serif(bd, size: 20, italic: true, color: bd.muted)),
              const Spacer(),
              TextAction('SIGN IN', size: 12, onTap: () => showAuthSheet(context, signup: false)),
              const SizedBox(width: 4),
              const ThemeToggleButton(),
            ]),
            const SizedBox(height: 40),
            Label('A drink diary', color: bd.faint),
            const SizedBox(height: 16),
            Text('Every night\ngets a square.', style: T.serif(bd, size: 54, height: .95)),
            const SizedBox(height: 24),
            Text(
              'Coffee, wine, a midnight kombucha — whatever you poured. Tap a day, log it in a breath, and watch the year quietly fill in.',
              style: T.sans(bd, color: bd.muted, height: 1.6),
            ),
            const SizedBox(height: 16),
            Text(
              'The squares darken the more you drink, so a month of habits is one glance, not a spreadsheet. Keep it private, or pour with friends.',
              style: T.sans(bd, color: bd.muted, height: 1.6),
            ),
            const SizedBox(height: 48),
            const YearPreview(),
            const SizedBox(height: 48),
            Label('Try it — tap a day', color: bd.faint),
            const SizedBox(height: 20),
            MonthCalendar(year: _y, month: _m, counts: countsByDate(entries), onSelect: _open, onPrev: () => _step(-1), onNext: () => _step(1), canNext: canNext),
            const SizedBox(height: 28),
            Text(
              entries.isEmpty ? 'Tap any day to log your first drink. No account needed yet.' : 'Logged on this device. Make a diary below and it comes with you.',
              textAlign: TextAlign.center,
              style: T.sans(bd, size: 14, color: bd.faint),
            ),
            const SizedBox(height: 72),
            Text('One tap a night.\nIt adds up.', style: T.serif(bd, size: 40, height: 1.05)),
            const SizedBox(height: 28),
            for (var i = 0; i < _ledger.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: bd.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 36, child: Padding(padding: const EdgeInsets.only(top: 4), child: Label((i + 1).toString().padLeft(2, '0'), color: bd.faint))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_ledger[i].$1, style: T.serif(bd, size: 19)),
                      const SizedBox(height: 6),
                      Text(_ledger[i].$2, style: T.sans(bd, color: bd.muted, height: 1.55)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 56),
            Glass(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(entries.isNotEmpty ? 'Keep what you logged.' : 'Start tonight.', style: T.serif(bd, size: 36, height: 1.05)),
                const SizedBox(height: 16),
                Text(
                  entries.isNotEmpty
                      ? 'Your entries live on this device until you make a diary. Sign up and they come with you — phone, laptop, next year.'
                      : 'A diary takes an email and a password. Free, no card, and the first square is one tap away.',
                  style: T.sans(bd, color: bd.muted, height: 1.6),
                ),
                const SizedBox(height: 28),
                InkButton('Create a diary', onTap: () {
                  _autoOpened = true;
                  showAuthSheet(context, signup: true);
                }),
              ]),
            ),
            if (!Config.cloud) ...[
              const SizedBox(height: 20),
              Text(
                'Running without a cloud backend — "Create a diary" keeps everything on this phone.',
                textAlign: TextAlign.center,
                style: T.sans(bd, size: 12, color: bd.faint),
              ),
            ],
          ],
        );
      },
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

/// Theme switch — reachable from every screen, so the app is never stuck in one theme.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) {
        final dark = ThemeStore.instance.isDark;
        return Semantics(
          label: 'Theme: ${dark ? 'Dark' : 'Light'}. Tap to switch.',
          button: true,
          child: GestureDetector(
            onTap: ThemeStore.instance.toggle,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dark ? bd.muted : Colors.transparent, border: Border.all(color: bd.muted, width: 1.5)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── the auth sheet ───────────────────────────────────────────────────────────
Future<void> showAuthSheet(BuildContext context, {required bool signup}) =>
    showBdSheet(context, builder: (_) => _AuthSheet(signup: signup));

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
  String? _error;
  bool _confirm = false;
  bool _resetSent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
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
        Text('Check your email.', style: T.serif(bd, size: 32)),
        const SizedBox(height: 12),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'We sent a confirmation link to ', style: T.sans(bd, color: bd.muted, height: 1.6)),
          TextSpan(text: _email.text, style: T.sans(bd)),
          TextSpan(text: '. Tap it to finish, then come back and sign in.', style: T.sans(bd, color: bd.muted, height: 1.6)),
        ])),
        const SizedBox(height: 24),
        InkButton('Go to sign in', onTap: () => setState(() {
              _confirm = false;
              _signup = false;
            })),
      ]);
    }
    final n = entryStore.entries.length;
    final kicker = _signup ? (n > 0 ? (n > 1 ? '$n nights logged' : 'First night logged') : 'New diary') : 'Welcome back';
    final ready = _email.text.trim().isNotEmpty && _password.text.length >= 6;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Label(kicker),
      const SizedBox(height: 12),
      Text(_signup ? 'Keep your diary.' : 'Sign in.', style: T.serif(bd, size: 32)),
      const SizedBox(height: 12),
      Text(_signup ? "Save what you logged and start a streak. Email and a password — that's it." : 'Pick up where you left off.', style: T.sans(bd, color: bd.muted, height: 1.6)),
      const SizedBox(height: 24),
      if (_signup) ...[
        const Label('Name'),
        const SizedBox(height: 6),
        LineField(controller: _name, hint: 'What should we call you?', caps: TextCapitalization.words, onChanged: (_) => setState(() {})),
        const SizedBox(height: 16),
      ],
      const Label('Email'),
      const SizedBox(height: 6),
      LineField(controller: _email, hint: 'you@email.com', keyboard: TextInputType.emailAddress, caps: TextCapitalization.none, onChanged: (_) => setState(() {})),
      const SizedBox(height: 16),
      const Label('Password'),
      const SizedBox(height: 6),
      LineField(controller: _password, hint: _signup ? 'At least 6 characters' : 'Your password', obscure: true, caps: TextCapitalization.none, onChanged: (_) => setState(() {}), onSubmitted: (_) => ready ? _submit() : null),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accent))),
      const SizedBox(height: 20),
      InkButton(_signup ? 'Start my diary' : 'Sign in', busy: _busy, onTap: ready ? _submit : null),
      if (!_signup)
        Center(
          child: _resetSent
              ? Padding(padding: const EdgeInsets.only(top: 12), child: Text('Reset link sent to ${_email.text} — check your inbox.', style: T.sans(bd, size: 12, color: bd.muted)))
              : TextAction('Forgot password?', size: 12, onTap: _busy ? null : _forgot),
        ),
      Center(
        child: TextAction(_signup ? 'Already have a diary? Sign in' : 'New here? Create a diary', size: 12, onTap: () => setState(() {
              _error = null;
              _signup = !_signup;
            })),
      ),
    ]);
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

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    final place = PlaceStore.instance;
    final required = place.legalAgeFor(_country);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Glass(
            strong: true,
            blur: true,
            padding: const EdgeInsets.all(28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('brewdiary', style: T.serif(bd, size: 20, italic: true, color: bd.muted)),
              const SizedBox(height: 16),
              if (_blocked) ...[
                Text('Not just yet.', style: T.serif(bd, size: 32)),
                const SizedBox(height: 12),
                Text('You need to be of legal drinking age where you are ($required+) to use brewdiary. Come back when you are.', style: T.sans(bd, color: bd.muted, height: 1.6)),
                const SizedBox(height: 20),
                Align(alignment: Alignment.centerLeft, child: TextAction('Re-enter date', faint: true, onTap: () => setState(() => _blocked = false))),
              ] else ...[
                Text('A quick check.', style: T.serif(bd, size: 32)),
                const SizedBox(height: 12),
                Text('brewdiary is a diary of what you drink — alcohol included. Confirm your date of birth to come in.', style: T.sans(bd, color: bd.muted, height: 1.6)),
                const SizedBox(height: 24),
                Label('Where you are', color: bd.faint),
                CountryPicker(value: _country, includeElsewhere: true, onChanged: (c) => setState(() => _country = c)),
                const SizedBox(height: 6),
                Text("The legal age differs by country — here it's $required+.", style: T.sans(bd, size: 12, color: bd.faint)),
                const SizedBox(height: 20),
                Label('Date of birth', color: bd.faint),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(now.year - 25, now.month, now.day),
                      firstDate: DateTime(now.year - 110),
                      lastDate: now,
                      initialEntryMode: DatePickerEntryMode.input,
                    );
                    if (picked != null) {
                      setState(() {
                        _dob = picked;
                        _error = null;
                      });
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: bd.lineStrong))),
                    child: Text(
                      _dob == null ? 'Tap to enter' : '${_dob!.day} ${monthNames[_dob!.month - 1]} ${_dob!.year}',
                      style: T.sans(bd, color: _dob == null ? bd.faint : bd.ink),
                    ),
                  ),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accent))),
                const SizedBox(height: 24),
                InkButton('Enter', onTap: () {
                  if (_dob == null) {
                    setState(() => _error = 'Please enter your date of birth.');
                    return;
                  }
                  if (!place.confirmAge(_dob!, _country == 'ZZ' ? null : _country)) setState(() => _blocked = true);
                }),
                const SizedBox(height: 16),
                Text(
                  "Please drink responsibly. Your date of birth isn't sent anywhere or saved — we check it, then keep only a yes on this device.",
                  style: T.sans(bd, size: 12, color: bd.faint, height: 1.5),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Country dropdown over the researched list (plus "Somewhere else" = strict).
class CountryPicker extends StatelessWidget {
  final String value;
  final bool includeElsewhere;
  final ValueChanged<String> onChanged;
  const CountryPicker({super.key, required this.value, required this.onChanged, this.includeElsewhere = false});
  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return DropdownButton<String>(
      value: value,
      isExpanded: true,
      dropdownColor: Color.alphaBlend(bd.glassStrong, bd.base),
      underline: Container(height: 1, color: bd.lineStrong),
      style: T.sans(bd),
      items: [
        for (final c in _countries) DropdownMenuItem(value: c.$1, child: Text(c.$2)),
        if (includeElsewhere) const DropdownMenuItem(value: 'ZZ', child: Text('Somewhere else')),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

// Imported lazily to keep the landing import list honest.
const _countries = <(String, String)>[
  ('IN', 'India'), ('AE', 'United Arab Emirates'), ('AU', 'Australia'), ('BR', 'Brazil'), ('CA', 'Canada'),
  ('DE', 'Germany'), ('ES', 'Spain'), ('FI', 'Finland'), ('FR', 'France'), ('GB', 'United Kingdom'),
  ('IE', 'Ireland'), ('IT', 'Italy'), ('JP', 'Japan'), ('KR', 'South Korea'), ('MX', 'Mexico'),
  ('NL', 'Netherlands'), ('NO', 'Norway'), ('NZ', 'New Zealand'), ('PL', 'Poland'), ('SE', 'Sweden'),
  ('SG', 'Singapore'), ('TH', 'Thailand'), ('TR', 'Türkiye'), ('US', 'United States'), ('ZA', 'South Africa'),
];
