import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/ledger_controller.dart';
import '../data/ledger_store.dart';
import '../screens/identity_screen.dart';
import '../security/app_lock.dart';
import '../screens/login_screen.dart';
import 'auth_service.dart';

/// Shows the login screen until a user is signed in, then [signedIn].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.signedIn});

  final AuthService auth;
  final Widget signedIn;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snap) {
        if (snap.data == null) return LoginScreen(auth: auth);
        // Just signed in: the ledger above may arrive a frame later, and my
        // profile a moment after that.
        final ledger = LedgerScope.maybeOf(context);
        if (ledger == null || !ledger.profileLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // No dashboard until I have said who I am (spec: Transfers between my own accounts).
        if (!ledger.setupDone) return const SetupScreen();
        return signedIn;
      },
    );
  }
}

/// Gives every screen (including pushed ones) the signed-in user's ledger.
/// It sits above the app's navigator; signing in as someone else starts a new one.
class UserLedger extends StatelessWidget {
  const UserLedger({super.key, required this.auth, required this.child});

  final AuthService auth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.userChanges,
      initialData: auth.currentUser,
      builder: (context, snap) {
        final uid = snap.data?.uid;
        if (uid == null) return child;
        // The lock sits above the navigator too, so it covers every screen.
        return LedgerHost(key: ValueKey(uid), store: FirestoreLedgerStore(uid), child: AppLock(auth: auth, child: child));
      },
    );
  }
}
