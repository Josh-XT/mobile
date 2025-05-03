import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Assuming ConfigService might use this eventually, or directly access env

import 'config_service.dart';
import 'settings_service.dart';

class ChatService {
  final ConfigService _configService;
  final SettingsService _settingsService;

  ChatService(this._configService, this._settingsService);

  Future<String?> sendChatMessage(String userMessage) async {
    final jwt = await _settingsService.getJwt();
    if (jwt == null || jwt.isEmpty) {
      print('Error: JWT token not found.');
      return null; // Or throw an exception/return specific error message
    }

    final apiUrl = '${_configService.agixtServer}/v1/chat/completions';
    final uri = Uri.parse(apiUrl);

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt', // Assuming Bearer prefix is standard
    };

    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd').format(now);

    final body = jsonEncode({
      'model': 'EVEN_REALITIES_GLASSES',
      'messages': [
        {'role': 'user', 'content': userMessage}
      ],
      'user': formattedDate,
    });

    try {
      final response = await http.post(uri, headers: headers, body: body);

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        // Safely access nested fields
        final choices = responseBody['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final firstChoice = choices[0] as Map?;
          if (firstChoice != null) {
            final message = firstChoice['message'] as Map?;
            if (message != null) {
              final content = message['content'] as String?;
              if (content != null) {
                return content;
              }
            }
          }
        }
        print('Error: Could not parse assistant message from response.');
        return null; // Indicate parsing failure
      } else {
        print('Error: API request failed with status code ${response.statusCode}');
        print('Response body: ${response.body}');
        // Handle specific error codes if needed (e.g., 401 for unauthorized)
        return null; // Indicate API error
      }
    } catch (e) {
      print('Error sending chat message: $e');
      return null; // Indicate network or other exception
    }
  }
}