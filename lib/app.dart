import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/litert_service.dart';
import 'services/storage_service.dart';
import 'services/cache_service.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/model_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/model_import_screen.dart';
import 'utils/theme.dart';

class RAIApp extends StatelessWidget {
  const RAIApp({super.key});

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

  final _screens = const [
    ChatScreen(),
    ModelImportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().loadSessions();
      context.read<ModelProvider>().loadModels();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
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
          indicatorColor: AppColors.primary.withOpacity(0.15),
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
}