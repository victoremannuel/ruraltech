import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/legacy_firebase_compat.dart';

class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
  });

  final String uid;
  final String? email;
}

class AuthService extends ChangeNotifier {
  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _authSub = _client.auth.onAuthStateChange.listen((_) {
      unawaited(_refreshProfile());
    });
    unawaited(_refreshProfile());
  }

  final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSub;

  AuthUser? _user;
  String? _role;
  bool _profileLoading = false;

  AuthUser? get user => _user;
  String get role => _role ?? 'user';
  bool get isAdmin => role == 'adm' || role == 'admin';
  bool get isProfileLoading => _profileLoading;

  Future<void> _refreshProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      _user = null;
      _role = null;
      _profileLoading = false;
      notifyListeners();
      return;
    }

    _profileLoading = true;
    notifyListeners();
    try {
      final email = authUser.email?.trim().toLowerCase();
      final profile = await _client
          .from('profiles')
          .select('legacy_uid, email, role')
          .eq('auth_user_id', authUser.id)
          .maybeSingle();

      Map<String, dynamic>? effectiveProfile;
      if (profile == null) {
        effectiveProfile = await _client
            .from('profiles')
            .upsert({
              'auth_user_id': authUser.id,
              'legacy_uid': authUser.id,
              'email': email,
              'role': 'user',
            })
            .select('legacy_uid, email, role')
            .single();
      } else {
        effectiveProfile = Map<String, dynamic>.from(profile);
      }

      final legacyUid =
          (effectiveProfile['legacy_uid'] ?? authUser.id).toString().trim();
      final normalizedEmail = ((effectiveProfile['email'] ?? email) as String?)
          ?.trim()
          .toLowerCase();
      final resolvedRole =
          (effectiveProfile['role'] as String?)?.trim().toLowerCase();

      _user = AuthUser(
        uid: legacyUid.isEmpty ? authUser.id : legacyUid,
        email: normalizedEmail?.isEmpty == true ? null : normalizedEmail,
      );
      _role =
          resolvedRole == null || resolvedRole.isEmpty ? 'user' : resolvedRole;
    } on AuthException catch (error) {
      throw FirebaseAuthException(
        code: error.statusCode?.toString() ?? 'auth_error',
        message: error.message,
      );
    } catch (_) {
      _user = AuthUser(
        uid: authUser.id,
        email: authUser.email?.trim().toLowerCase(),
      );
      _role = 'user';
    } finally {
      _profileLoading = false;
      notifyListeners();
    }
  }

  FirebaseAuthException _mapAuthException(Object error) {
    if (error is FirebaseAuthException) {
      return error;
    }
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return FirebaseAuthException(
          code: 'invalid-credential',
          message: error.message,
        );
      }
      if (message.contains('email not confirmed')) {
        return FirebaseAuthException(
          code: 'email-not-confirmed',
          message: error.message,
        );
      }
      if (message.contains('password should be at least')) {
        return FirebaseAuthException(
          code: 'weak-password',
          message: error.message,
        );
      }
      if (message.contains('already registered') ||
          message.contains('user already registered')) {
        return FirebaseAuthException(
          code: 'email-already-in-use',
          message: error.message,
        );
      }
      if (message.contains('invalid email')) {
        return FirebaseAuthException(
          code: 'invalid-email',
          message: error.message,
        );
      }
      if (message.contains('over_email_send_rate_limit') ||
          message.contains('rate limit')) {
        return FirebaseAuthException(
          code: 'too-many-requests',
          message: error.message,
        );
      }
      return FirebaseAuthException(
        code: error.statusCode?.toString() ?? 'auth_error',
        message: error.message,
      );
    }
    return FirebaseAuthException(
      code: 'auth_error',
      message: error.toString(),
    );
  }

  Future<void> signIn(String email, String pass) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: pass,
      );
      await _refreshProfile();
    } catch (error) {
      throw _mapAuthException(error);
    }
  }

  Future<void> signUp(String email, String pass) async {
    try {
      await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: pass,
      );
      await _refreshProfile();
    } catch (error) {
      throw _mapAuthException(error);
    }
  }

  Future<void> updateRole(String uid, String role) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      throw FirebaseException(
        plugin: 'supabase',
        code: 'invalid_uid',
        message: 'UID invalido.',
      );
    }
    await _client.from('profiles').update(
        {'role': role.trim().toLowerCase()}).eq('legacy_uid', normalizedUid);
    if (_user?.uid == normalizedUid) {
      _role = role.trim().toLowerCase();
      notifyListeners();
    }
  }

  Future<void> updateRoleByEmail(String email, String role) async {
    final normalizedEmail = email.trim().toLowerCase();
    final profile = await _client
        .from('profiles')
        .select('legacy_uid')
        .eq('email', normalizedEmail)
        .maybeSingle();
    if (profile == null) {
      throw FirebaseException(
        plugin: 'supabase',
        code: 'user_not_found',
        message: 'Usuario com esse email nao foi encontrado.',
      );
    }
    await updateRole((profile['legacy_uid'] ?? '').toString(), role);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _user = null;
    _role = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
