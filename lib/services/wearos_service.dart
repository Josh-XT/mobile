import 'package:flutter/services.dart';

class WearOSService {
  static const platform = MethodChannel('com.example.app/wearos');

  Future<void> sendChatResponseToWearOS(String response) async {
    try {
      await platform.invokeMethod('sendChatResponse', {'response': response});
    } catch (e) {
      print('Failed to send response to WearOS: $e');
    }
  }
}