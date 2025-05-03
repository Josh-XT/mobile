import 'package:flutter/material.dart';

class GlassProvider with ChangeNotifier {
  String _leftStatus = 'Disconnected';
  String _rightStatus = 'Disconnected';

  String get leftStatus => _leftStatus;
  String get rightStatus => _rightStatus;

  void updateLeftStatus(String status) {
    _leftStatus = status;
    notifyListeners();
  }

  void updateRightStatus(String status) {
    _rightStatus = status;
    notifyListeners();
  }
}