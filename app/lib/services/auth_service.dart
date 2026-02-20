import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  User? get user => _auth.currentUser;
  String? _role;
  bool _profileLoading = false;

  String get role => _role ?? 'user';
  bool get isAdmin => role == 'adm';
  bool get isProfileLoading => _profileLoading;

  AuthService() {
    _auth.authStateChanges().listen((u) async {
      if (u == null) {
        _role = null;
        notifyListeners();
        return;
      }
      await _loadOrCreateProfile(u);
      notifyListeners();
    });
  }

  Future<void> _loadOrCreateProfile(User u) async {
    _profileLoading = true;
    notifyListeners();
    try {
      final ref = _db.collection('users').doc(u.uid);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'uid': u.uid,
          'email': u.email?.toLowerCase(),
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _role = 'user';
      } else {
        final data = snap.data() ?? {};
        _role = (data['role'] as String?) ?? 'user';
      }
    } finally {
      _profileLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn(String email, String pass) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: pass,
    );
  }

  Future<void> signUp(String email, String pass) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: pass,
    );
    final u = cred.user;
    if (u != null) {
      await _db.collection('users').doc(u.uid).set({
        'uid': u.uid,
        'email': u.email?.toLowerCase(),
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _role = 'user';
      notifyListeners();
    }
  }

  Future<void> updateRole(String uid, String role) async {
    await _db.collection('users').doc(uid).set({
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (user?.uid == uid) {
      _role = role;
      notifyListeners();
    }
  }

  Future<void> updateRoleByEmail(String email, String role) async {
    final normalizedEmail = email.trim().toLowerCase();
    final snap = await _db
        .collection('users')
        .where('email', isEqualTo: normalizedEmail)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      throw Exception('Usuario com esse email nao foi encontrado.');
    }

    final doc = snap.docs.first;
    await updateRole(doc.id, role);
  }

  Future<void> signOut() => _auth.signOut();
}
