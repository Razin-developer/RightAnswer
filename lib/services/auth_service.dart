import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

class AuthUser {
  final String id;
  final String email;
  final String name;

  const AuthUser({required this.id, required this.email, required this.name});

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: j['_id'] as String? ?? j['id'] as String,
        email: j['email'] as String,
        name: j['name'] as String? ?? '',
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
      await _storage.delete(key: _tokenKey);
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

  Future<void> requestPasswordReset(String email) async {
    await ApiService.instance.post(
      '/api/auth/reset-password/request',
      {'email': email},
      auth: false,
    );
  }

  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    await ApiService.instance.post(
      '/api/auth/reset-password/confirm',
      {'token': token, 'newPassword': newPassword},
      auth: false,
    );
  }

  Future<AuthUser> _saveSession(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: user.id);
    await _storage.write(key: _userEmailKey, value: user.email);
    await _storage.write(key: _userNameKey, value: user.name);
    _currentUser = user;
    return user;
  }
}
