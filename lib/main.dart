import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/litert_service.dart';
import 'services/storage_service.dart';
import 'services/cache_service.dart';
import 'services/embedding_service.dart';
import 'services/tool_service.dart';
import 'services/session_database_service.dart';
import 'services/ram_monitor_service.dart';
import 'services/permission_service.dart';
import 'services/log_service.dart';
import 'providers/rag_provider.dart';
import 'providers/embedding_model_provider.dart';
import 'providers/tool_provider.dart';
import 'providers/session_provider.dart';

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

  // Initialize logging service first
  final logService = LogService();
  await logService.initialize();
  logService.log('Main', 'App starting...');

  // Initialize permission service
  final permissionService = PermissionService();
  final hasPermission = await permissionService.checkManageStoragePermission();
  logService.log('Main', 'Storage permission status: $hasPermission');

  if (!hasPermission) {
    logService.log('Main', 'Requesting storage permission...');
    final granted = await permissionService.requestManageStoragePermission();
    logService.log('Main', 'Storage permission granted: $granted');
  }

  final storageService = await StorageService.getInstance();
  final cacheService = await CacheService.getInstance();
  final litertService = LiteRTService();
  final embeddingService = EmbeddingService(logService: logService);
  final toolService = ToolService();
  final sessionDbService = await SessionDatabaseService.getInstance();
  final ramMonitorService = RamMonitorService();

  final embeddingModelProvider = EmbeddingModelProvider(
    embeddingService: embeddingService,
    cacheService: cacheService,
    logService: logService,
  );

  final ragProvider = RagProvider(
    embeddingProvider: embeddingModelProvider,
  );

  final toolProvider = ToolProvider(
    toolService: toolService,
    cacheService: cacheService,
  );

  final sessionProvider = SessionProvider(
    dbService: sessionDbService,
  );

  // Load persisted state
  await embeddingModelProvider.loadModels();
  await ragProvider.loadDatabases();
  await toolProvider.loadTools();
  await sessionProvider.loadSessions();

  // Start RAM monitoring
  ramMonitorService.startMonitoring();

  logService.log('Main', 'App initialization complete');

  runApp(
    MultiProvider(
      providers: [
        Provider<LiteRTService>.value(value: litertService),
        Provider<StorageService>.value(value: storageService),
        Provider<CacheService>.value(value: cacheService),
        Provider<EmbeddingService>.value(value: embeddingService),
        Provider<ToolService>.value(value: toolService),
        Provider<SessionDatabaseService>.value(value: sessionDbService),
        Provider<RamMonitorService>.value(value: ramMonitorService),
        Provider<PermissionService>.value(value: permissionService),
        Provider<LogService>.value(value: logService),
        ChangeNotifierProvider<EmbeddingModelProvider>.value(
          value: embeddingModelProvider,
        ),
        ChangeNotifierProvider<RagProvider>.value(value: ragProvider),
        ChangeNotifierProvider<ToolProvider>.value(value: toolProvider),
        ChangeNotifierProvider<SessionProvider>.value(value: sessionProvider),
      ],
      child: const RAIApp(),
    ),
  );
}
