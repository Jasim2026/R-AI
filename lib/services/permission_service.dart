import 'package:flutter/services.dart';

class PermissionService {
  static const MethodChannel _channel = MethodChannel('com.rai/permissions');

  Future<bool> checkManageStoragePermission() async {
    try {
      final result = await _channel.invokeMethod('checkManageStoragePermission');
      return result as bool;
    } on PlatformException catch (e) {
      print('Error checking storage permission: ${e.message}');
      return false;
    }
  }

  Future<bool> requestManageStoragePermission() async {
    try {
      final result = await _channel.invokeMethod('requestManageStoragePermission');
      return result as bool;
    } on PlatformException catch (e) {
      print('Error requesting storage permission: ${e.message}');
      return false;
    }
  }

  Future<bool> isManageStorageGranted() async {
    try {
      final result = await _channel.invokeMethod('isManageStorageGranted');
      return result as bool;
    } on PlatformException catch (e) {
      print('Error checking if storage granted: ${e.message}');
      return false;
    }
  }
}
