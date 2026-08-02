import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'services/litert_service.dart';
import 'services/storage_service.dart';
import 'services/cache_service.dart';
import 'services/embedding_service.dart';
import 'providers/rag_provider.dart';
import 'providers/embedding_model_provider.dart';

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

  final storageService = await StorageService.getInstance();
  final cacheService = await CacheService.getInstance();
  final litertService = LiteRTService();
  final embeddingService = EmbeddingService();

  final embeddingModelProvider = EmbeddingModelProvider(
    embeddingService: embeddingService,
    cacheService: cacheService,
  );

  final ragProvider = RagProvider(
    embeddingProvider: embeddingModelProvider,
  );

  // Load persisted state
  await embeddingModelProvider.loadModels();
  await ragProvider.loadDatabases();

  runApp(
    MultiProvider(
      providers: [
        Provider<LiteRTService>.value(value: litertService),
        Provider<StorageService>.value(value: storageService),
        Provider<CacheService>.value(value: cacheService),
        Provider<EmbeddingService>.value(value: embeddingService),
        ChangeNotifierProvider<EmbeddingModelProvider>.value(
          value: embeddingModelProvider,
        ),
        ChangeNotifierProvider<RagProvider>.value(value: ragProvider),
      ],
      child: const RAIApp(),
    ),
  );
}
