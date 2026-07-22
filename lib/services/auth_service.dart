// auth_service.dart - updated signUp method
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper around FirebaseAuth + the "users" collection in Firestore.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    // Check if it's an email or username
    if (emailOrUsername.contains('@')) {
      // It's an email
      return await _auth.signInWithEmailAndPassword(
        email: emailOrUsername.trim(),
        password: password,
      );
    } else {
      // It's a username - find the email from Firestore
      final querySnapshot = await _db
          .collection('users')
          .where('username', isEqualTo: emailOrUsername.trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No account found with that username.',
        );
      }

      final email = querySnapshot.docs.first.data()['email'] as String;
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    }
  }

  Future<UserCredential> signUp({
    required String username,
    required String name,
    required String email,
    required String password,
  }) async {
    // Check if username is already taken
    final usernameQuery = await _db
        .collection('users')
        .where('username', isEqualTo: username.trim())
        .limit(1)
        .get();

    if (usernameQuery.docs.isNotEmpty) {
      throw FirebaseAuthException(
        code: 'username-taken',
        message: 'This username is already taken.',
      );
    }

    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Use username as display name
    await cred.user?.updateDisplayName(username.trim());

    // Create a matching user profile document in Firestore
    await _db.collection('users').doc(cred.user!.uid).set({
      'username': username.trim(),
      'name': username.trim(), // Store username as name too
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
          return 'No account found with that email or username.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email/username or password.';
        case 'email-already-in-use':
          return 'An account already exists with that email.';
        case 'weak-password':
          return 'Password is too weak (use at least 6 characters).';
        case 'username-taken':
          return 'This username is already taken.';
        default:
          return e.message ?? 'Something went wrong. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  // Helper method to get username from user ID
  Future<String?> getUsername(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      return doc.data()?['username'] as String?;
    } catch (e) {
      return null;
    }
  }

  // Helper method to get all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final querySnapshot = await _db.collection('users').get();
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'uid': doc.id,
          'username': data['username'] as String? ?? 'Unknown',
          'name': data['name'] as String? ?? 'Unknown',
          'email': data['email'] as String? ?? '',
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }
}