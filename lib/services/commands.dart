import 'dart:convert';
import '../models/notification.dart'; // Corrected import path
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/settings_service.dart'; // Import SettingsService for JWT
import '../services/config_service.dart'; // Import ConfigService for server URL

import '../services/bluetooth_manager.dart';

enum Command {
  START_AI(0xF5),
  OPEN_MIC(0x0E),
  MIC_RESPONSE(0x0E),
  RECEIVE_MIC_DATA(0xF1),
  INIT(0x4D),
  HEARTBEAT(0x25),
  SEND_RESULT(0x4E),
  QUICK_NOTE(0x21),
  DASHBOARD(0x22),
  NOTIFICATION(0x4B);

  final int value;
  const Command(this.value);
}

class SendResult {
  final Command command;
  final int seq;
  final int totalPackages;
  final int currentPackage;
  final int screenStatus;
  final int newCharPos0;
  final int newCharPos1;
  final int pageNumber;
  final int maxPages;
  final List<int> data;

  SendResult({
    required this.command,
    this.seq = 0,
    this.totalPackages = 1,
    this.currentPackage = 0,
    this.screenStatus = 0x31, // Example value
    this.newCharPos0 = 0,
    this.newCharPos1 = 0,
    this.pageNumber = 1,
    this.maxPages = 1,
    required this.data,
  });

  List<int> build() {
    return [
      command.value,
      seq & 0xFF,
      totalPackages & 0xFF,
      currentPackage & 0xFF,
      screenStatus & 0xFF,
      newCharPos0 & 0xFF,
      newCharPos1 & 0xFF,
      pageNumber & 0xFF,
      maxPages & 0xFF,
      ...data,
    ];
  }
}

// Define AIStatus and ScreenAction constants
class AIStatus {
  static const int DISPLAYING = 0x20;
  static const int DISPLAY_COMPLETE = 0x40;
}

class ScreenAction {
  static const int NEW_CONTENT = 0x10;
}

List<int> constructHeartbeat(int seq) {
  int length = 6;
  return [
    Command.HEARTBEAT.value,
    length & 0xFF,
    (length >> 8) & 0xFF,
    seq % 0xFF,
    0x04,
    seq % 0xFF,
  ];
}

List<String> formatTextLines(String textMessage) {
  // Assuming a maximum line length of 20 characters
  const int maxLineLength = 20;
  List<String> words = textMessage.split(' ');
  List<String> lines = [];
  String currentLine = '';

  for (String word in words) {
    if ((currentLine + word).length <= maxLineLength) {
      currentLine += (currentLine.isEmpty ? '' : ' ') + word;
    } else {
      lines.add(currentLine);
      currentLine = word;
    }
  }
  if (currentLine.isNotEmpty) {
    lines.add(currentLine);
  }
  return lines;
}

Future<String?> sendTextPacket({
  required String textMessage,
  required BluetoothManager bluetoothManager,
  int pageNumber = 1,
  int maxPages = 1,
  int screenStatus = ScreenAction.NEW_CONTENT | AIStatus.DISPLAYING,
  int delay = 400,
  int seq = 0,
}) async {
  List<int> textBytes = utf8.encode(textMessage);

  SendResult result = SendResult(
    command: Command.SEND_RESULT,
    seq: seq,
    totalPackages: 1,
    currentPackage: 0,
    screenStatus: screenStatus,
    newCharPos0: 0,
    newCharPos1: 0,
    pageNumber: pageNumber,
    maxPages: maxPages,
    data: textBytes,
  );

  List<int> aiResultCommand = result.build();

  try {
    if (bluetoothManager.leftGlass != null && bluetoothManager.rightGlass != null) {


      // Send to the left glass and wait
      await bluetoothManager.leftGlass!.sendData(aiResultCommand);
      await Future.delayed(Duration(milliseconds: delay));

      // Send to the right glass and wait
      await bluetoothManager.rightGlass!.sendData(aiResultCommand);
      await Future.delayed(Duration(milliseconds: delay));


      return textMessage;
    } else {
      print("Could not connect to glasses devices.");
      return null;
    }
  } catch (e) {
    print('Error in sendTextPacket: $e');
    return null;
  }
}

Future<String?> sendText(String textMessage, BluetoothManager bluetoothManager, {double duration = 5.0}) async {
  List<String> lines = formatTextLines(textMessage);
  int totalPages = ((lines.length + 4) / 5).ceil(); // 5 lines per page

  if (totalPages > 1) {
    print("Sending $totalPages pages with $duration seconds delay");
    int screenStatus = AIStatus.DISPLAYING | ScreenAction.NEW_CONTENT;

    await sendTextPacket(
      textMessage: lines[0],
      bluetoothManager: bluetoothManager,
      pageNumber: 1,
      maxPages: totalPages,
      screenStatus: screenStatus,
    );
    await Future.delayed(Duration(milliseconds: 100));
  }

  String lastPageText = '';

  for (int pn = 1, page = 0; page < lines.length; pn++, page += 5) {
    List<String> pageLines = lines.sublist(
      page,
      (page + 5) > lines.length ? lines.length : (page + 5),
    );

    // Add vertical centering for pages with fewer than 5 lines
    if (pageLines.length < 5) {
      int padding = ((5 - pageLines.length) / 2).floor();
      pageLines = List.filled(padding, '') +
          pageLines +
          List.filled(5 - pageLines.length - padding, '');
    }

    String text = pageLines.join('\n');
    lastPageText = text;
    int screenStatus = AIStatus.DISPLAYING | ScreenAction.NEW_CONTENT;

    await sendTextPacket(
      textMessage: text,
      bluetoothManager: bluetoothManager,
      pageNumber: pn,
      maxPages: totalPages,
      screenStatus: screenStatus,
    );

    // Wait after sending each page except the last one
    if (pn != totalPages) {
      await Future.delayed(Duration(seconds: duration.ceil()));
    }
  }

  // After all pages, send the last page again with DISPLAY_COMPLETE status
  int screenStatus = AIStatus.DISPLAY_COMPLETE;

  await sendTextPacket(
    textMessage: lastPageText,
    bluetoothManager: bluetoothManager,
    pageNumber: totalPages,
    maxPages: totalPages,
    screenStatus: screenStatus,
  );

  return textMessage;
}

Future<void> sendNotification(String message, BluetoothManager bluetoothManager) async {

  NCSNotification notification = NCSNotification(
    msgId: 1,
    type: 1,
    appIdentifier: 'org.telegram.messenger',
    title: 'Notification Title',
    subtitle: 'Notification Subtitle',
    message: message,
    displayName: "Test App",
  );

  Notification ntf = Notification(ncsNotification: notification);

  List<List<int>> notificationChunks = await ntf.constructNotification();

  try {
    if (bluetoothManager.leftGlass != null && bluetoothManager.rightGlass != null) {
      for (int i = 0; i < notificationChunks.length; i++) {
        await bluetoothManager.leftGlass!.sendData(notificationChunks[i]);
        await Future.delayed(Duration(milliseconds: 100));
        await bluetoothManager.rightGlass!.sendData(notificationChunks[i]);
        await Future.delayed(Duration(milliseconds: 100));
      }
    } else {
      print("Could not connect to glasses devices.");
    }
  } catch (e) {
    print('Error in sendNotification: $e');
  }
}

// Updated to accept required services
Future<String?> sendChatRequest(
    String userMessage,
    SettingsService settingsService,
    ConfigService configService, // Added ConfigService for server URL
    ) async {
  final jwt = await settingsService.getJwt(); // Use SettingsService
  if (jwt == null) {
    throw Exception('JWT not found. User needs to log in.');
  }

  final serverUrl = configService.agixtServer; // Use ConfigService
  if (serverUrl.isEmpty) {
     throw Exception('AGiXT server URL not configured.');
  }

  try {
    final response = await http.post(
      Uri.parse('$serverUrl/v1/chat/completions'), // Use configured server URL
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt', // Add Bearer prefix
      },
      body: jsonEncode({
        'model': 'EVEN_REALITIES_GLASSES', // Consider making this configurable
        'messages': [
          {'role': 'user', 'content': userMessage},
        ],
        'user': DateFormat('yyyy-MM-dd').format(DateTime.now()), // Consider if user ID is better
      }),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      // Check response structure carefully
      if (responseBody != null &&
          responseBody['choices'] is List &&
          responseBody['choices'].isNotEmpty &&
          responseBody['choices'][0]['message'] is Map &&
          responseBody['choices'][0]['message']['content'] != null) {
        return responseBody['choices'][0]['message']['content'];
      } else {
        throw Exception('Unexpected chat response format.');
      }
    } else if (response.statusCode == 401) {
      // JWT has expired, clear it and throw specific exception
      await settingsService.clearJwt(); // Use SettingsService
      throw Exception('Authentication expired. Please log in again.');
    } else {
      // Try to parse error detail from backend
      String errorDetail = response.body;
      try {
         final errorJson = jsonDecode(response.body);
         if (errorJson['detail'] != null) {
            errorDetail = errorJson['detail'];
         }
      } catch (_) { /* Ignore JSON parsing error */ }
      throw Exception('Failed to get chat response (${response.statusCode}): $errorDetail');
    }
  } catch (e) {
    print('Error in sendChatRequest: $e');
    throw e;
  }
}