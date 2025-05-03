import 'package:flutter/foundation.dart'; // Import ChangeNotifier
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfigService with ChangeNotifier { // Mixin ChangeNotifier
  // Private constructor
  ConfigService._() {
    // Load environment variables upon instantiation
    loadEnv();
  }

  // Static instance
  static final ConfigService _instance = ConfigService._();

  // Factory constructor to return the static instance
  factory ConfigService() {
    return _instance;
  }

  // Instance method to load environment variables and notify listeners
  Future<void> loadEnv() async {
    try {
      await dotenv.load(fileName: ".env");
      print("ConfigService: .env loaded.");
      notifyListeners(); // Notify listeners after loading
    } catch (e) {
      print("ConfigService: Error loading .env file: $e");
      // Handle error or use default values
      // Still notify listeners even if defaults are used or error occurs
      notifyListeners();
    }
  }

  // Getters for environment variables with defaults
  String get appName => dotenv.env['APP_NAME'] ?? 'AGiXT';
  String get agixtServer => dotenv.env['AGIXT_SERVER'] ?? ''; // Default to empty string
  String get appUri => dotenv.env['APP_URI'] ?? ''; // Default to empty string

  // Getter to check if the server is configured
  bool get isConfigured => agixtServer.isNotEmpty && Uri.tryParse(agixtServer)?.isAbsolute == true;
}