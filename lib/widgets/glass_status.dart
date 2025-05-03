import 'package:flutter/material.dart';

class GlassStatus extends StatelessWidget {
  final String side;
  final String status;

  const GlassStatus({
    Key? key,
    required this.side,
    required this.status,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color statusColor;

    switch (status) {
      case 'Connected':
        statusColor = Colors.green;
        break;
      case 'Connecting...':
      case 'Scanning...':
        statusColor = Colors.orange;
        break;
      case 'Disconnected':
      case 'Scan Timeout':
      case 'Scan Error':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Column(
      children: [
        Text(
          '$side Glass',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 5),
        Text(
          status,
          style: TextStyle(color: statusColor),
        ),
      ],
    );
  }
}