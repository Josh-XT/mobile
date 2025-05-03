import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _jwtKey = 'jwt';

  // Store JWT securely
  static Future<void> storeJWT(String jwt) async {
    await _storage.write(key: _jwtKey, value: jwt);
  }

  // Retrieve JWT
  static Future<String?> getJWT() async {
    return await _storage.read(key: _jwtKey);
  }

  // Clear JWT (logout)
  static Future<void> clearJWT() async {
    await _storage.delete(key: _jwtKey);
  }

  // Check if JWT exists
  static Future<bool> hasJWT() async {
    final jwt = await getJWT();
    return jwt != null && jwt.isNotEmpty;
  }

  // Check if JWT is valid (not expired)
  static Future<bool> isJWTValid() async {
    final jwt = await getJWT();
    if (jwt == null || jwt.isEmpty) {
      return false;
    }

    try {
      // JWT consists of 3 parts separated by dots
      final parts = jwt.split('.');
      if (parts.length != 3) {
        return false;
      }

      // Decode the payload (middle part)
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final Map<String, dynamic> data = jsonDecode(decoded);

      // Check expiration
      if (data.containsKey('exp')) {
        final exp = DateTime.fromMillisecondsSinceEpoch(data['exp'] * 1000);
        return exp.isAfter(DateTime.now());
      }

      // If no explicit expiration, check if it's before the first day of the next month
      final now = DateTime.now();
      final firstDayOfNextMonth = DateTime(now.year, now.month + 1, 1);
      return now.isBefore(firstDayOfNextMonth);
    } catch (e) {
      print('Error validating JWT: $e');
      return false;
    }
  }
}