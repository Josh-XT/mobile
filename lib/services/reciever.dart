import 'dart:typed_data';
import 'dart:convert'; // For potential future text conversion

import 'chat_service.dart'; // Import the new service

// Command response status codes
const int RESPONSE_SUCCESS = 0xC9;
const int RESPONSE_FAILURE = 0xCA;

// Voice data buffer to collect chunks
class VoiceDataCollector {
  final Map<int, List<int>> _chunks = {};
  int _expectedSeq = 0;

  void addChunk(int seq, List<int> data) {
    _chunks[seq] = data;
  }

  bool get isComplete => _chunks.length > 0 && !_chunks.containsKey(_expectedSeq);
  
  List<int> getAllData() {
    List<int> complete = [];
    for (var i = 0; i < _chunks.length; i++) {
      if (_chunks.containsKey(i)) {
        complete.addAll(_chunks[i]!);
      }
    }
    return complete;
  }

  void reset() {
    _chunks.clear();
    _expectedSeq = 0;
  }
}

final VoiceDataCollector voiceCollector = VoiceDataCollector();

Future<void> receiveHandler(String side, List<int> data, ChatService chatService) async { // Add ChatService parameter
  if (data.isEmpty) return;

  int command = data[0];
  
  switch (command) {
    case 0xF5: // Start Even AI
      if (data.length >= 2) {
        int subcmd = data[1];
        handleEvenAICommand(side, subcmd, chatService); // Pass chatService
      }
      break;
      
    case 0x0E: // Mic Response
      if (data.length >= 3) {
        int status = data[1];
        int enable = data[2];
        handleMicResponse(side, status, enable);
      }
      break;
      
    case 0xF1: // Voice Data
      if (data.length >= 2) {
        int seq = data[1];
        List<int> voiceData = data.sublist(2);
        handleVoiceData(side, seq, voiceData);
      }
      break;
      
    default:
      print('[$side] Unknown command: 0x${command.toRadixString(16)}');
  }
}

void handleEvenAICommand(String side, int subcmd, ChatService chatService) async { // Add ChatService parameter and make async
  switch (subcmd) {
    case 0:
      print('[$side] Exit to dashboard manually');
      break;
    case 1:
      print('[$side] Page ${side == 'left' ? 'up' : 'down'} control');
      break;
    case 23:
      print('[$side] Start Even AI');
      break;
    case 24:
      print('[$side] Stop Even AI recording');
      // Process collected voice data
      if (voiceCollector.isComplete) {
        List<int> completeVoiceData = voiceCollector.getAllData();
        print('[$side] Complete voice data received, length: ${completeVoiceData.length}');

        // --- Voice Data Processing Placeholder ---
        // TODO: Implement actual voice data processing (e.g., LC3 decoding, Speech-to-Text)
        // For now, we'll send a placeholder message.
        String userMessage = "Placeholder: Voice input received.";
        // --- End Placeholder ---

        print('[$side] Sending message to ChatService: "$userMessage"');
        final assistantResponse = await chatService.sendChatMessage(userMessage);

        if (assistantResponse != null) {
          print('[$side] ChatService Response: $assistantResponse');
          // TODO: Send assistantResponse back to the glasses display
        } else {
          print('[$side] ChatService returned null or error.');
        }

        voiceCollector.reset();
      } else {
         print('[$side] Stop command received, but voice data collection is not complete.');
         voiceCollector.reset(); // Reset anyway to avoid inconsistent state
      }
      break;
  }
}

void handleMicResponse(String side, int status, int enable) {
  if (status == RESPONSE_SUCCESS) {
    print('[$side] Mic ${enable == 1 ? "enabled" : "disabled"} successfully');
  } else if (status == RESPONSE_FAILURE) {
    print('[$side] Failed to ${enable == 1 ? "enable" : "disable"} mic');
  }
}

void handleVoiceData(String side, int seq, List<int> voiceData) {
  print('[$side] Received voice data chunk: seq=$seq, length=${voiceData.length}');
  voiceCollector.addChunk(seq, voiceData);
}