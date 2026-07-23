import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String role;
  // 'hobby' | 'pro' | 'scholar' — see PlansService/PlansScreen. Defaults to
  // 'hobby' for any response that predates this field (cached sessions).
  final String plan;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.role = 'user',
    this.plan = 'hobby',
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['id'] as String? ?? j['_id'] as String,
        email: j['email'] as String,
        name: j['name'] as String? ?? '',
        role: j['role'] as String? ?? 'user',
        plan: j['plan'] as String? ?? 'hobby',
      );
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'ra_jwt';
  static const _userIdKey = 'ra_user_id';
  static const _userEmailKey = 'ra_user_email';
  static const _userNameKey = 'ra_user_name';
  static const _userPlanKey = 'ra_user_plan';

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<void> init() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return;
    try {
      final data = await ApiService.instance.get('/api/auth/me');
      _currentUser = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    } catch (_) {
      _currentUser = await _readCachedUser();
    }
  }

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<AuthUser> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final data = await ApiService.instance.post(
      '/api/auth/register',
      {'email': email, 'password': password, 'name': name},
      auth: false,
    );
    return _saveSession(data);
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final data = await ApiService.instance.post(
      '/api/auth/login',
      {'email': email, 'password': password},
      auth: false,
    );
    return _saveSession(data);
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    _currentUser = null;
  }

  /// Updates the display name server-side and refreshes the cached session.
  /// Throws [ApiException]/[ApiException]-wrapped network errors — callers
  /// should catch and show a friendly message.
  Future<AuthUser> updateName(String name) async {
    final data = await ApiService.instance.put('/api/auth/me', {
      'name': name,
    });
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _userNameKey, value: user.name);
    _currentUser = user;
    return user;
  }

  /// Changes the account password. The backend independently verifies
  /// [oldPassword] against the stored hash — a wrong value surfaces as an
  /// [ApiException] with a clear "Current password is incorrect" message.
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await ApiService.instance.post('/api/auth/change-password', {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  /// Re-fetches the session user from the server — used after a plan
  /// purchase completes so [currentUser] reflects the new plan without
  /// requiring the user to log out/in. Returns the cached user unchanged
  /// on failure (offline, server hiccup) rather than throwing, since
  /// callers use this as a best-effort refresh, not a critical path.
  Future<AuthUser?> refreshUser() async {
    try {
      final data = await ApiService.instance.get('/api/auth/me');
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      await _storage.write(key: _userNameKey, value: user.name);
      await _storage.write(key: _userPlanKey, value: user.plan);
      _currentUser = user;
      return user;
    } catch (_) {
      return _currentUser;
    }
  }

  // NOTE: The backend has no password-reset endpoints yet (no SMTP
  // configured). Do not add calls here until `/api/auth/reset-password/*`
  // actually exists server-side — see ForgotPasswordScreen for the honest
  // "not available yet" messaging shown to users instead.

  Future<AuthUser> _saveSession(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: user.id);
    await _storage.write(key: _userEmailKey, value: user.email);
    await _storage.write(key: _userNameKey, value: user.name);
    await _storage.write(key: _userPlanKey, value: user.plan);
    _currentUser = user;
    return user;
  }

  Future<AuthUser?> _readCachedUser() async {
    final id = await _storage.read(key: _userIdKey);
    final email = await _storage.read(key: _userEmailKey);
    if (id == null || email == null) return null;
    final name = await _storage.read(key: _userNameKey) ?? '';
    final plan = await _storage.read(key: _userPlanKey) ?? 'hobby';
    return AuthUser(id: id, email: email, name: name, plan: plan);
  }
}
