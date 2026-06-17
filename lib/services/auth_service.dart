// =============================================================================
// Auth Service — Firebase Authentication Wrapper
// =============================================================================
// Wraps FirebaseAuth for sign-in, sign-out, and auth state streaming.
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Stream of auth state changes — null when signed out, User when signed in
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Currently signed-in user (null if not signed in)
  static User? get currentUser => _auth.currentUser;

  /// Sign in with email and password.
  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  /// Create a new user account (Used by Admin).
  static Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
  }

  /// Sign in with Doctor ID by looking up associated email in Firestore.
  /// Throws [FirebaseAuthException] or custom error if ID not found.
  static Future<UserCredential> signInWithDoctorId({
    required String doctorId,
    required String password,
  }) async {
    // 1. Find the doctor in Firestore by ID + domain
    final String fullEmail = doctorId.contains('@') ? doctorId.trim() : "${doctorId.trim()}@moh.om";
    
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(fullEmail)
        .get();

    // FALLBACK: If ID not found in Firestore, try a direct email sign-in (for Admins)
    if (!doc.exists) {
      try {
        final credential = await signIn(email: doctorId.contains('@') ? doctorId : fullEmail, password: password);
        
        // SELF-HEALING: If this is the master admin account and it's missing from Firestore, recreate it!
        if (fullEmail.toLowerCase() == 'admin@moh.om') {
          await FirebaseFirestore.instance.collection('users').doc(fullEmail).set({
            'name': 'System Administrator',
            'email': fullEmail,
            'role': 'admin',
            'password': password, // Store for legacy sync
            'createdAt': FieldValue.serverTimestamp(),
          });
          // Re-fetch to continue normally
          return credential;
        }
        
        return credential;
      } catch (e) {
        throw FirebaseAuthException(
          code: 'doctor-id-not-found',
          message: 'Account not found. Please verify your Staff ID or Email.',
        );
      }
    }

    final data = doc.data() as Map<String, dynamic>;
    final email = data['email'] as String? ?? '';
    final storedPassword = data['password'] as String? ?? '';

    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'This account has no email associated with it.',
      );
    }

    // 2. Try to Sign In
    try {
      final credential = await signIn(email: email, password: password);
    await _logAction(email, 'Login');
    return credential;
    } on FirebaseAuthException catch (e) {
      // 3. IF THE USER DOESN'T EXIST IN AUTH YET
      // Check if the typed password matches the one the Admin set in Firestore
      if (e.code == 'invalid-credential' || e.code == 'user-not-found') {
        if (password == storedPassword) {
          // Create the Auth account on the fly!
          final credential = await signUp(email: email, password: password);
          await _logAction(email, 'Login (Recovered)');
          return credential;
        }
      }
      rethrow;
    }
  }

  /// Resolve a Staff ID or email to the Firebase Auth email address.
  static Future<String> resolveEmail(String doctorId) async {
    final trimmed = doctorId.trim();
    final fullEmail =
        trimmed.contains('@') ? trimmed : '$trimmed@moh.om';

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(fullEmail.toLowerCase())
        .get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final email = (data['email'] as String? ?? fullEmail).trim();
      if (email.isNotEmpty) return email.toLowerCase();
    }

    // Fallback: use constructed email if account may exist in Auth only
    return fullEmail.toLowerCase();
  }

  /// Send a password reset email for the given Staff ID or email.
  /// Returns the email address the reset was sent to.
  static Future<String> sendPasswordReset({required String doctorId}) async {
    final email = await resolveEmail(doctorId);

    // Verify account exists in Firestore before sending (avoid silent failures)
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(email)
        .get();

    if (!doc.exists) {
      // Also try lookup by email field
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No account found for this Staff ID or email.',
        );
      }
    }

    await _auth.sendPasswordResetEmail(email: email);
    await _logAction(email, 'Password Reset Requested');
    return email;
  }

  /// Sign out current user and log the action
  static Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _logAction(user.email ?? 'Unknown', 'Logout');
    }
    await _auth.signOut();
  }

  /// Internal helper to log security events to Firestore
  static Future<void> _logAction(String userEmail, String action) async {
    try {
      await FirebaseFirestore.instance.collection('system_logs').add({
        'email': userEmail,
        'action': action,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': 'Mobile App',
      });
    } catch (e) {
      debugPrint('Logging failed: $e');
    }
  }

  /// Convert a [FirebaseAuthException] code into a user-friendly message.
  static String friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'invalid-credential':
        return 'Invalid credentials. Check your ID and password.';
      case 'doctor-id-not-found':
        return 'Doctor ID not found. Please verify your ID.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
