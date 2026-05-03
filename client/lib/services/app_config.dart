import 'dart:convert';
import 'dart:io';

class AppConfig {
  static AppConfig? _instance;

  final String? signalUrl;
  final String? apiUrl;
  final String configPath;
  final String loadStatus;

  AppConfig._({
    this.signalUrl,
    this.apiUrl,
    required this.configPath,
    required this.loadStatus,
  });

  static AppConfig get instance {
    _instance ??= _load();
    return _instance!;
  }

  static AppConfig _load() {
    String exeDir = '';
    try {
      exeDir = File(Platform.resolvedExecutable).parent.path;
      final configFile = File('$exeDir\\config.json');
      if (!configFile.existsSync()) {
        return AppConfig._(
          configPath: configFile.path,
          loadStatus: 'not found',
        );
      }
      final raw = configFile.readAsStringSync();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppConfig._(
        signalUrl: (json['signal_url'] as String?)?.trim(),
        apiUrl: (json['api_url'] as String?)?.trim(),
        configPath: configFile.path,
        loadStatus: 'ok',
      );
    } catch (e) {
      return AppConfig._(
        configPath: exeDir.isEmpty ? '(unknown)' : '$exeDir\\config.json',
        loadStatus: 'error: $e',
      );
    }
  }
}
