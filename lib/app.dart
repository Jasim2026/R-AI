import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/litert_service.dart';
import 'services/storage_service.dart';
import 'services/cache_service.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/model_provider.dart';
import 'providers/rag_provider.dart';
import 'providers/embedding_model_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/model_import_screen.dart';
import 'utils/theme.dart';

class RAIApp extends StatefulWidget {
  const RAIApp({super.key});

  @override
  State<RAIApp> createState() => _RAIAppState();
}

class _RAIAppState extends State<RAIApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => SettingsProvider(
            cacheService: context.read<CacheService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ModelProvider(
            litertService: context.read<LiteRTService>(),
            storageService: context.read<StorageService>(),
            cacheService: context.read<CacheService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ChatProvider(
            litertService: context.read<LiteRTService>(),
            storageService: context.read<StorageService>(),
            cacheService: context.read<CacheService>(),
            ragProvider: context.read<RagProvider>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'R-AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        context.read<ChatProvider>().loadSessions();
        context.read<ModelProvider>().loadModels();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentScreen(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
              width: 0.5,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          backgroundColor: AppColors.surfaceDark,
          indicatorColor: const Color(0x266C63FF),
          height: 70,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded, size: 22),
              selectedIcon: Icon(Icons.chat_bubble_rounded, size: 22),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: Icon(Icons.memory_outlined, size: 22),
              selectedIcon: Icon(Icons.memory_rounded, size: 22),
              label: 'Models',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, size: 22),
              selectedIcon: Icon(Icons.settings_rounded, size: 22),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return const ChatScreen();
      case 1:
        return const ModelImportScreen();
      case 2:
        return const SettingsScreen();
      default:
        return const ChatScreen();
    }
  }
}
