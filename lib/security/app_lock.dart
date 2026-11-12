import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../auth/auth_service.dart';
import '../data/ledger_controller.dart';
import '../platform/emailjs.dart';
import '../platform/leaving_app.dart';

const passcodeLength = 4;

/// A salted SHA-256 of the passcode. Only this and the salt are stored (in my
/// private profile), never the digits.
String hashPasscode(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

String newSalt() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// Locks the whole app (every screen, since it sits above the navigator) when
/// it opens and whenever I leave it for another app. Asks me to create a
/// passcode first if I have none.
class AppLock extends StatefulWidget {
  const AppLock({super.key, required this.auth, required this.child});

  final AuthService auth;
  final Widget child;

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  bool _locked = true; // a fresh start always asks

  // "Forgot passcode?": the emailed code, kept only in memory for 10 minutes.
  final _mailer = ResetCodeMailer();
  String? _codeEmail, _code;
  DateTime? _codeExpires;
  bool _resetting = false; // the code was right; now setting a new passcode

  Future<String?> _sendCode(String email) async {
    final r = Random.secure();
    final code = List.generate(6, (_) => r.nextInt(10)).join();
    try {
      await _mailer.send(email: email, code: code);
    } on EmailException catch (e) {
      return 'Could not email the code (${e.message}).'; // the service's own reason, e.g. a setting
    } catch (_) {
      return 'Could not email the code. Check the connection and try again.';
    }
    if (mounted) {
      setState(() {
        _codeEmail = email;
        _code = code;
        _codeExpires = DateTime.now().add(const Duration(minutes: 10));
      });
    }
    return null;
  }

  void _forgetCode() => setState(() => _codeEmail = _code = _codeExpires = null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !expectingExternal && !_locked) setState(() => _locked = true);
    if (state == AppLifecycleState.resumed) expectingExternal = false;
  }

  /// "Forgot passcode?": choose my Google account, then a code is emailed to
  /// it; entering that code lets me set a new passcode.
  Future<String?> _forgot() async {
    final before = widget.auth.currentUser?.uid;
    expectExternal();
    try {
      await widget.auth.signInWithGoogle(chooseAccount: true);
    } on GoogleSignInException catch (e) {
      return e.code == GoogleSignInExceptionCode.canceled ? null : 'Google sign-in failed.';
    } catch (_) {
      return 'Google sign-in failed.';
    }
    // Another account: that account's own lock takes over.
    if (widget.auth.currentUser?.uid != before) return null;
    final email = widget.auth.currentUser?.email;
    if (email == null) return 'This Google account has no email address.';
    return _sendCode(email);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    // Before setup the app's own gate shows sign-in and setup screens.
    if (!c.profileLoaded || !c.setupDone) return widget.child;
    final Widget? cover = !c.hasPasscode
        ? _CreatePasscode(
            title: _resetting ? 'Set a new passcode' : 'Create a passcode',
            subtitle: _resetting ? 'Your email is confirmed. Choose a new 4-digit passcode.' : null,
            onDone: (pin) {
              c.setPasscode(pin);
              setState(() => _locked = _resetting = false); // confirmed: open the app
            },
          )
        : _locked && _codeEmail != null
            ? _EnterCode(
                email: _codeEmail!,
                check: (code) {
                  if (DateTime.now().isAfter(_codeExpires!)) return 'This code has expired. Send a new one.';
                  if (code != _code) return 'Wrong code.';
                  _resetting = true;
                  _forgetCode();
                  c.clearPasscode(); // the lock now asks for a new passcode
                  return null;
                },
                onResend: () => _sendCode(_codeEmail!),
                onBack: _forgetCode,
              )
            : _locked
            ? _EnterPasscode(
                check: c.checkPasscode,
                onUnlocked: () => setState(() => _locked = false),
                onForgot: _forgot,
                // Back to the login page; after signing in, the passcode is still asked.
                onSignIn: widget.auth.signOut,
              )
            : null;
    if (cover == null) return widget.child;
    // The app stays underneath (keeps its place), covered by the lock, which
    // has its own navigator for text, overlays and routes.
    return Stack(children: [
      widget.child,
      // Keyed by step: a Navigator builds its first page only once, so without
      // this the passcode page would stay up after the code was emailed.
      Positioned.fill(
        child: Navigator(key: ValueKey(cover.runtimeType), onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => cover)),
      ),
    ]);
  }
}

class _EnterPasscode extends StatefulWidget {
  const _EnterPasscode({required this.check, required this.onUnlocked, required this.onForgot, required this.onSignIn});
  final bool Function(String) check;
  final VoidCallback onUnlocked;
  final Future<String?> Function() onForgot;
  final Future<void> Function() onSignIn;

  @override
  State<_EnterPasscode> createState() => _EnterPasscodeState();
}

class _EnterPasscodeState extends State<_EnterPasscode> {
  static const maxTries = 5;
  int _wrong = 0;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final out = _wrong >= maxTries;
    return PinPad(
      title: out ? 'Too many tries' : 'Enter your passcode',
      subtitle: out ? 'Use Forgot passcode? to set a new one.' : _error,
      enabled: !out,
      onComplete: (pin) {
        if (widget.check(pin)) {
          widget.onUnlocked();
          return true;
        }
        setState(() {
          _wrong++;
          _error = _wrong >= maxTries ? null : 'Wrong passcode. ${maxTries - _wrong} tries left.';
        });
        return false;
      },
      footer: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton(
          onPressed: () async {
            final err = await widget.onForgot();
            if (err != null && mounted) setState(() => _error = err);
          },
          child: const Text('Forgot passcode?'),
        ),
        TextButton(onPressed: widget.onSignIn, child: const Text('Sign in with Google')),
      ]),
    );
  }
}

/// The 6-digit code from the "Forgot passcode" email.
class _EnterCode extends StatefulWidget {
  const _EnterCode({required this.email, required this.check, required this.onResend, required this.onBack});
  final String email;

  /// Null when right, else the message to show.
  final String? Function(String code) check;
  final Future<String?> Function() onResend;
  final VoidCallback onBack;

  @override
  State<_EnterCode> createState() => _EnterCodeState();
}

class _EnterCodeState extends State<_EnterCode> {
  static const maxTries = 5;
  int _wrong = 0;
  String? _message;

  /// "a•••@gmail.com", so the address is recognisable but not shown in full.
  String get _masked {
    final at = widget.email.indexOf('@');
    return at <= 1 ? widget.email : '${widget.email[0]}•••${widget.email.substring(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final out = _wrong >= maxTries;
    return PinPad(
      length: 6,
      title: out ? 'Too many tries' : 'Check your email',
      subtitle: _message ??
          (out ? 'Send a new code.' : 'We sent a 6-digit code to $_masked. Enter it below. It works for 10 minutes.'),
      enabled: !out,
      onComplete: (code) {
        final error = widget.check(code);
        if (error == null) return true;
        setState(() {
          _wrong++;
          _message = error;
        });
        return false;
      },
      footer: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton(onPressed: widget.onBack, child: const Text('Back')),
        TextButton(
          onPressed: () async {
            final err = await widget.onResend();
            if (mounted) {
              setState(() {
                _wrong = 0;
                _message = err ?? 'A new code was sent.';
              });
            }
          },
          child: const Text('Send a new code'),
        ),
      ]),
    );
  }
}

/// New passcode, entered twice.
class _CreatePasscode extends StatefulWidget {
  const _CreatePasscode({required this.onDone, this.title = 'Create a passcode', this.subtitle});
  final String? subtitle;
  final void Function(String pin) onDone;
  final String title;

  @override
  State<_CreatePasscode> createState() => _CreatePasscodeState();
}

class _CreatePasscodeState extends State<_CreatePasscode> {
  String? _first;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return PinPad(
      key: ValueKey(_first == null),
      title: _first == null ? widget.title : 'Enter it again',
      subtitle: _error ??
          (_first == null ? (widget.subtitle ?? 'Asked whenever you open FinTrack or come back to it.') : 'Confirm your new passcode.'),
      onComplete: (pin) {
        if (_first == null) {
          setState(() {
            _first = pin;
            _error = null;
          });
        } else if (pin == _first) {
          widget.onDone(pin);
        } else {
          setState(() {
            _first = null;
            _error = 'They did not match. Start again.';
          });
        }
        return true;
      },
    );
  }
}

/// Settings → Change passcode: the current one, then the new one twice.
class ChangePasscodeScreen extends StatefulWidget {
  const ChangePasscodeScreen({super.key});

  @override
  State<ChangePasscodeScreen> createState() => _ChangePasscodeScreenState();
}

class _ChangePasscodeScreenState extends State<ChangePasscodeScreen> {
  bool _verified = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final c = LedgerScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Change passcode')),
      body: _verified
          ? _CreatePasscode(
              title: 'New passcode',
              onDone: (pin) {
                c.setPasscode(pin);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcode changed')));
              },
            )
          : PinPad(
              title: 'Current passcode',
              subtitle: _error,
              onComplete: (pin) {
                if (c.checkPasscode(pin)) {
                  setState(() => _verified = true);
                  return true;
                }
                setState(() => _error = 'Wrong passcode.');
                return false;
              },
            ),
    );
  }
}

/// Dots and a number pad. [onComplete] returns false for a wrong entry, which
/// clears the dots.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onComplete,
    this.subtitle,
    this.footer,
    this.enabled = true,
    this.length = passcodeLength,
  });

  final int length;
  final String title;
  final String? subtitle;
  final bool Function(String pin) onComplete;
  final Widget? footer;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _tap(String d) {
    if (!widget.enabled || _pin.length >= widget.length) return;
    setState(() => _pin += d);
    if (_pin.length == widget.length) {
      final pin = _pin;
      // Let the last dot show, then check.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        widget.onComplete(pin);
        if (mounted) setState(() => _pin = '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, String? tooltip}) => Expanded(
          child: AspectRatio(
            aspectRatio: 1.6,
            child: InkResponse(
              onTap: onTap,
              radius: 40,
              child: Center(
                child: icon != null
                    ? Icon(icon, semanticLabel: tooltip)
                    : Text(label, style: theme.textTheme.headlineSmall),
              ),
            ),
          ),
        );
    Widget row(List<String> ds) => Row(children: [for (final d in ds) key(d, onTap: () => _tap(d))]);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(children: [
            const Spacer(),
            Icon(Icons.lock_outline, size: 40, color: scheme.onSurface),
            const SizedBox(height: 16),
            Text(widget.title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: Text(widget.subtitle ?? '', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: '${_pin.length} of ${widget.length} digits entered',
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < widget.length; i++)
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: widget.length > 4 ? 7 : 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? scheme.onSurface : Colors.transparent,
                      border: Border.all(color: scheme.onSurface, width: 1.5),
                    ),
                  ),
              ]),
            ),
            const Spacer(),
            row(['1', '2', '3']),
            row(['4', '5', '6']),
            row(['7', '8', '9']),
            Row(children: [
              const Expanded(child: SizedBox()),
              key('0', onTap: () => _tap('0')),
              key('', icon: Icons.backspace_outlined, tooltip: 'Delete', onTap: () {
                if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
              }),
            ]),
            const SizedBox(height: 8),
            ?widget.footer,
          ]),
        ),
      ),
    );
  }
}
