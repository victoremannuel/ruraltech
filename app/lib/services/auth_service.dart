import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? get user => _auth.currentUser;

  AuthService() {
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  Future<void> signIn(String email, String pass) => _auth.signInWithEmailAndPassword(email: email, password: pass);
  Future<void> signUp(String email, String pass) => _auth.createUserWithEmailAndPassword(email: email, password: pass);
  Future<void> signOut() => _auth.signOut();
}
