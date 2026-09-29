// Sign in with the same brewdiary account as the website: an emailed 6-digit code (no
// password to forget), or a password. New staff can create an account the same way.
import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../../data/session.dart';
import '../theme.dart';
import '../widgets/bits.dart';
import '../widgets/common.dart';

enum _Step { email, code, password }

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  _Step _step = _Step.email;
  bool _create = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on BackendError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() => _go(() async {
        final email = _email.text.trim();
        if (!email.contains('@')) throw const BackendError('Type the email you use for brewdiary.');
        await Backend.i.sendEmailCode(email, create: _create, name: _name.text);
        setState(() => _step = _Step.code);
      });

  Future<void> _verify() => _go(() async {
        await Backend.i.verifyEmailCode(_email.text, _code.text);
        await Session.instance.adoptCurrentUser();
      });

  Future<void> _passwordSignIn() => _go(() async {
        await Backend.i.signInWithPassword(_email.text, _password.text);
        await Session.instance.adoptCurrentUser();
      });

  @override
  Widget build(BuildContext context) {
    final bd = context.bd;
    return Scaffold(
      body: Ambient(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: S.gutter, vertical: S.x3),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('brewdiary bar', style: T.serif(bd, size: 40, italic: true)),
                  const SizedBox(height: S.s),
                  Text('Run the floor and know your regulars — for bars, restaurants, cafés, clubs and shops.', style: T.bodyMuted(bd)),
                  const SizedBox(height: S.x3),
                  const DemoNote(),
                  Glass(
                    padding: const EdgeInsets.all(S.xl),
                    child: AnimatedSize(duration: Motion.med, child: _form(bd)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: S.m),
                    Semantics(liveRegion: true, child: Text(_error!, style: T.sans(bd, size: 14, color: bd.accentText))),
                  ],
                  const SizedBox(height: S.xl),
                  Text('The same account as bwdy.site. Your diary stays yours — the venue app never shows it to anyone.', style: T.caption(bd)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BD bd) {
    switch (_step) {
      case _Step.email:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_create ? 'Create your account' : 'Sign in', style: T.title(bd)),
          const SizedBox(height: S.l),
          if (_create) ...[
            LineField(controller: _name, label: 'Your name', hint: 'As your team knows you', caps: TextCapitalization.words, autofill: const [AutofillHints.name]),
            const SizedBox(height: S.l),
          ],
          LineField(
            controller: _email,
            label: 'Email',
            hint: 'you@yourbar.com',
            keyboard: TextInputType.emailAddress,
            caps: TextCapitalization.none,
            autofill: const [AutofillHints.email],
            action: TextInputAction.go,
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: S.xl),
          BdButton('Email me a code', busy: _busy, onTap: _sendCode),
          const SizedBox(height: S.s),
          if (!_create) BdButton('Use a password instead', kind: BtnKind.quiet, onTap: () => setState(() => _step = _Step.password)),
          TextAction(_create ? 'I already have an account' : 'New here? Create an account', accent: true, onTap: () => setState(() => _create = !_create)),
        ]);
      case _Step.code:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Check your email', style: T.title(bd)),
          const SizedBox(height: S.s),
          Text('We sent a 6-digit code to ${_email.text.trim()}. It works for 10 minutes.', style: T.bodyMuted(bd)),
          const SizedBox(height: S.l),
          LineField(
            controller: _code,
            label: 'Code',
            hint: '123456',
            keyboard: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            autofill: const [AutofillHints.oneTimeCode],
            action: TextInputAction.done,
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: S.xl),
          BdButton('Sign in', busy: _busy, onTap: _verify),
          const SizedBox(height: S.s),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextAction('Use another email', onTap: () => setState(() => _step = _Step.email)),
            TextAction('Send a new code', accent: true, onTap: _busy ? null : _sendCode),
          ]),
        ]);
      case _Step.password:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Sign in', style: T.title(bd)),
          const SizedBox(height: S.l),
          LineField(controller: _email, label: 'Email', keyboard: TextInputType.emailAddress, caps: TextCapitalization.none, autofill: const [AutofillHints.email]),
          const SizedBox(height: S.l),
          LineField(
            controller: _password,
            label: 'Password',
            obscure: true,
            caps: TextCapitalization.none,
            autofill: const [AutofillHints.password],
            action: TextInputAction.go,
            onSubmitted: (_) => _passwordSignIn(),
          ),
          const SizedBox(height: S.xl),
          BdButton('Sign in', busy: _busy, onTap: _passwordSignIn),
          const SizedBox(height: S.s),
          BdButton('Email me a code instead', kind: BtnKind.quiet, onTap: () => setState(() => _step = _Step.email)),
        ]);
    }
  }
}
