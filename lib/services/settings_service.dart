import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  final _storage = const FlutterSecureStorage();
  static const _jwtKey = 'user_jwt';

  // Private constructor
  SettingsService._();

  // Static instance
  static final SettingsService _instance = SettingsService._();

  // Factory constructor to return the static instance
  factory SettingsService() {
    return _instance;
  }

  /// Saves the JWT token securely.
  Future<void> saveJwt(String jwt) async {
    await _storage.write(key: _jwtKey, value: jwt);
  }

  /// Retrieves the JWT token. Returns null if not found.
  Future<String?> getJwt() async {
    return await _storage.read(key: _jwtKey);
  }

  /// Clears the stored JWT token.
  Future<void> clearJwt() async {
    await _storage.delete(key: _jwtKey);
  }
}