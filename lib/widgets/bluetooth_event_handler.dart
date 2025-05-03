import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Import Provider
import '../services/commands.dart';
import '../services/bluetooth_manager.dart';
import '../services/settings_service.dart'; // Import SettingsService
import '../services/config_service.dart'; // Import ConfigService
import '../screens/login_screen.dart';
import 'dart:async';
import '../services/wearos_service.dart';

class BluetoothEventHandler extends StatefulWidget {
  final BluetoothManager bluetoothManager;

  const BluetoothEventHandler({Key? key, required this.bluetoothManager}) : super(key: key);

  @override
  _BluetoothEventHandlerState createState() => _BluetoothEventHandlerState();
}

class _BluetoothEventHandlerState extends State<BluetoothEventHandler> {
  final TextEditingController _inputController = TextEditingController();
  final WearOSService _wearOSService = WearOSService();
  bool _processing = false;

  // This would be connected to the actual side button event from the glasses
  Future<void> handleSideButtonPress() async {
    if (_processing) return; // Prevent multiple concurrent requests
    
    setState(() {
      _processing = true;
    });
    
    try {
      final userMessage = _inputController.text.isNotEmpty 
          ? _inputController.text 
          : "Hello, how can I help you today?"; // Default message
      
      // Show processing message on glasses
      await sendText("Processing your request...", widget.bluetoothManager);
      
      // Get required services from Provider
      final settingsService = Provider.of<SettingsService>(context, listen: false);
      final configService = Provider.of<ConfigService>(context, listen: false);

      // Send request to AGiXT with required services
      final response = await sendChatRequest(userMessage, settingsService, configService);

      if (response != null) {
        // Display response on glasses
        await sendText(response, widget.bluetoothManager, duration: 10.0);
        
        // Send the response to WearOS
        await _wearOSService.sendChatResponseToWearOS(response);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Response displayed on glasses')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Handle authentication errors
        if (e.toString().contains('Authentication expired') || 
            e.toString().contains('JWT not found')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authentication expired. Please log in again.')),
          );
          
          // Redirect to login screen
          await Future.delayed(const Duration(seconds: 2));
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          }
        } else {
          // Handle other errors
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
          // Display error on glasses
          await sendText("Sorry, an error occurred. Please try again.", widget.bluetoothManager);
        }
      }
    } finally {
      setState(() {
        _processing = false;
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextField(
            controller: _inputController,
            decoration: const InputDecoration(
              labelText: 'Message for AGiXT',
              hintText: 'Type your message to AGiXT here...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ),
        ElevatedButton.icon(
          onPressed: _processing ? null : handleSideButtonPress,
          icon: _processing 
              ? const SizedBox(
                  width: 20, 
                  height: 20, 
                  child: CircularProgressIndicator(strokeWidth: 2)
                )
              : const Icon(Icons.send),
          label: Text(_processing ? 'Processing...' : 'Send to AGiXT'),
        ),
      ],
    );
  }
}