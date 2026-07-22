import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around FirebaseAuth + the "users" collection in Firestore.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await cred.user?.updateDisplayName(name.trim());

    // Create a matching user profile document in Firestore.
    await _db.collection('users').doc(cred.user!.uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    return cred;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> resetPassword(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Turns raw FirebaseAuthException codes into human-readable text.
  String friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return 'That email address looks invalid.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
          return 'No account found with that email.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account already exists with that email.';
        case 'weak-password':
          return 'Password is too weak (use at least 6 characters).';
        default:
          return e.message ?? 'Something went wrong. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
