class AppConstants {
  AppConstants._();

  static const String appName = 'R-AI';
  static const String appVersion = '1.0.0';
  static const String defaultSystemPrompt =
      'You are a helpful, harmless, and honest AI assistant.';
  static const int maxTokens = 4096;
  static const double temperature = 0.7;
  static const double topP = 0.9;
  static const int maxChatHistory = 50;
  static const String modelsDir = 'models';
  static const String cacheDir = 'cache';
}