import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/glass.dart';
import '../models/notification.dart' as custom_notification;
import '../models/notification.dart';
import '../services/bluetooth_manager.dart';
import '../services/commands.dart';
import '../services/auth_service.dart';
import '../widgets/glass_status.dart';
import '../widgets/bluetooth_event_handler.dart';
import 'login_screen.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final BluetoothManager bluetoothManager = BluetoothManager();
  final TextEditingController _textController = TextEditingController();

  // Variables to hold connection status
  String leftStatus = 'Disconnected';
  String rightStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    // Optionally initiate scan here or via button
  }

  Future<void> _requestPermissions() async {
    // Your existing permission request logic
  }

  void _scanAndConnect() async {
    try {
      setState(() {
        leftStatus = 'Scanning...';
        rightStatus = 'Scanning...';
      });

      await bluetoothManager.startScanAndConnect(
        onGlassFound: (Glass glass) async {
          print('Glass found: ${glass.name} (${glass.side})');
          await _connectToGlass(glass);
        },
        onScanTimeout: (message) {
          print('Scan timeout: $message');
          setState(() {
            if (bluetoothManager.leftGlass == null) {
              leftStatus = 'Not Found';
            }
            if (bluetoothManager.rightGlass == null) {
              rightStatus = 'Not Found';
            }
          });
        },
        onScanError: (error) {
          print('Scan error: $error');
          setState(() {
            leftStatus = 'Scan Error';
            rightStatus = 'Scan Error';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scan error: $error')),
          );
        },
      );
    } catch (e) {
      print('Error in _scanAndConnect: $e');
      setState(() {
        leftStatus = 'Error';
        rightStatus = 'Error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _connectToGlass(Glass glass) async {
    await glass.connect();
    setState(() {
      if (glass.side == 'left') {
        leftStatus = 'Connecting...';
      } else {
        rightStatus = 'Connecting...';
      }
    });

    // Monitor connection
    glass.device.connectionState.listen((BluetoothConnectionState state) {
      if (glass.side == 'left') {
        leftStatus = state.toString().split('.').last;
      } else {
        rightStatus = state.toString().split('.').last;
      }
      setState(() {}); // Update the UI
      print('[${glass.side} Glass] Connection state: $state');
      if (state == BluetoothConnectionState.disconnected) {
        print('[${glass.side} Glass] Disconnected, attempting to reconnect...');
        setState(() {
          if (glass.side == 'left') {
            leftStatus = 'Reconnecting...';
          } else {
            rightStatus = 'Reconnecting...';
          }
        });
        _reconnectGlass(glass);
      }
    });
  }

  Future<void> _reconnectGlass(Glass glass) async {
    try {
      await glass.connect();
      print('[${glass.side} Glass] Reconnected.');
      setState(() {
        if (glass.side == 'left') {
          leftStatus = 'Connected';
        } else {
          rightStatus = 'Connected';
        }
      });
    } catch (e) {
      print('[${glass.side} Glass] Reconnection failed: $e');
      setState(() {
        if (glass.side == 'left') {
          leftStatus = 'Disconnected';
        } else {
          rightStatus = 'Disconnected';
        }
      });
    }
  }

  void _sendText() async {
    String text = _textController.text;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some text to send')),
      );
      return;
    }

    if (bluetoothManager.leftGlass != null && bluetoothManager.rightGlass != null) {
      await sendText(
        text,
        bluetoothManager,
        duration: 5.0,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Glasses are not connected')),
      );
    }
  }

  void _sendNotification() async {
    String message = _textController.text;
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message to send')),
      );
      return;
    }

    if (bluetoothManager.leftGlass != null && bluetoothManager.rightGlass != null) {
      await sendNotification(message, bluetoothManager);
    } else { 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Glasses are not connected')),
      );
    }
  }

  void _goToAGiXTWeb() async {
    final jwt = await AuthService.getJWT();
    if (jwt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication token not found')),
      );
      return;
    }
    
    final appUri = const String.fromEnvironment('APP_URI');
    final url = Uri.parse('$appUri?token=$jwt');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $appUri')),
      );
    }
  }

  void _logout() async {
    await AuthService.clearJWT();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    bluetoothManager.leftGlass?.disconnect();
    bluetoothManager.rightGlass?.disconnect();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appName = const String.fromEnvironment('APP_NAME', defaultValue: 'AGiXT');

    return Scaffold(
      appBar: AppBar(
        title: Text('$appName Glasses Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _scanAndConnect,
              child: const Text('Connect to Glasses'),
            ),
            const SizedBox(height: 20),
            // Display connection statuses using GlassStatus widget
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlassStatus(side: 'Left', status: leftStatus),
                GlassStatus(side: 'Right', status: rightStatus),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Enter text to send',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _sendText,
                    child: const Text('Send Text'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _sendNotification,
                    child: const Text('Send Notification'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              '$appName Integration',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // AGiXT Bluetooth Event Handler - controls side button functionality
            BluetoothEventHandler(bluetoothManager: bluetoothManager),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _goToAGiXTWeb,
              icon: const Icon(Icons.open_in_browser),
              label: Text('Go to $appName'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}