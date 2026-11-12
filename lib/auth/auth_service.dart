import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_config.dart';

/// Google sign-in through Firebase Auth, so only I can read my data.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static Future<void>? _init;

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// [chooseAccount] forgets the last Google account first, so the picker shows.
  Future<void> signInWithGoogle({bool chooseAccount = false}) async {
    final google = GoogleSignIn.instance;
    await (_init ??= google.initialize(serverClientId: googleWebClientId));
    if (chooseAccount) await google.signOut();
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google did not return an ID token.');
    await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}
