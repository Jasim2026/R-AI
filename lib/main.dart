import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app.dart';
import 'screens/permission_screen.dart';
import 'services/litert_service.dart';
import 'services/storage_service.dart';
import 'services/cache_service.dart';
import 'providers/rag_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF12121A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final hasPermission = await _checkStoragePermission();

  final storageService = await StorageService.getInstance();
  final cacheService = await CacheService.getInstance();
  final litertService = LiteRTService();

  runApp(
    MultiProvider(
      providers: [
        Provider<LiteRTService>.value(value: litertService),
        Provider<StorageService>.value(value: storageService),
        Provider<CacheService>.value(value: cacheService),
        ChangeNotifierProvider<RagProvider>(
          create: (_) => RagProvider.lazy(),
        ),
      ],
      child: RAIApp(hasPermission: hasPermission),
    ),
  );
}

Future<bool> _checkStoragePermission() async {
  var status = await Permission.storage.status;
  if (status.isGranted) {
    final manageStatus = await Permission.manageExternalStorage.status;
    return manageStatus.isGranted || manageStatus.isLimited;
  }
  return false;
}
