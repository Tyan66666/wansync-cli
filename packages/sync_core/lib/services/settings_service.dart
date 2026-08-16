import 'dart:convert';
import 'dart:io';

/// 抽象的键值存储接口，App 用 SecureSettingsStore（flutter_secure_storage），
/// CLI 用 FileSettingsStore / MapSettingsStore（纯 Dart）。
abstract class SettingsStore {
  Future<Map<String, String>> readAll();

  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});
}

/// 内存实现（测试用）。
class MapSettingsStore implements SettingsStore {
  final Map<String, String> _values;

  MapSettingsStore([Map<String, String>? initial]) : _values = {...?initial};

  @override
  Future<Map<String, String>> readAll() async => Map.of(_values);

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}

/// JSON 文件实现（CLI 用）：持久化到单个文件，键值扁平存储。
class FileSettingsStore implements SettingsStore {
  final File file;

  FileSettingsStore(this.file);

  Map<String, String> _load() {
    if (!file.existsSync()) return <String, String>{};
    try {
      final data = jsonDecode(file.readAsStringSync());
      if (data is Map) {
        return <String, String>{
          for (final entry in data.entries)
            if (entry.value != null)
              entry.key.toString(): entry.value.toString(),
        };
      }
    } catch (_) {
      // 损坏文件按空配置处理
    }
    return <String, String>{};
  }

  void _save(Map<String, String> values) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(values));
  }

  @override
  Future<Map<String, String>> readAll() async => _load();

  @override
  Future<String?> read({required String key}) async => _load()[key];

  @override
  Future<void> write({required String key, required String value}) async {
    final values = _load();
    values[key] = value;
    _save(values);
  }
}

class SettingsService {
  SettingsService({SettingsStore? store})
    : _store = store ?? MapSettingsStore();

  final SettingsStore _store;

  static const keyOneLapUsername = 'ONELAP_USERNAME';
  static const keyOneLapPassword = 'ONELAP_PASSWORD';
  static const keyStravaClientId = 'STRAVA_CLIENT_ID';
  static const keyStravaClientSecret = 'STRAVA_CLIENT_SECRET';
  static const keyStravaRefreshToken = 'STRAVA_REFRESH_TOKEN';
  static const keyStravaAccessToken = 'STRAVA_ACCESS_TOKEN';
  static const keyStravaExpiresAt = 'STRAVA_EXPIRES_AT';
  static const keyStravaUploadMode = 'STRAVA_UPLOAD_MODE';
  static const keyStravaWebCookies = 'STRAVA_WEB_COOKIES';
  static const keyXingzheUsername = 'XINGZHE_USERNAME';
  static const keyXingzhePassword = 'XINGZHE_PASSWORD';
  static const keyXingzheSessionId = 'XINGZHE_SESSION_ID';
  static const keyLookbackDays = 'LOOKBACK_DAYS';
  static const keyGcjCorrectionEnabled = 'GCJ_CORRECTION_ENABLED';
  static const keyUploadToStrava = 'UPLOAD_TO_STRAVA';
  static const keyUploadToXingzhe = 'UPLOAD_TO_XINGZHE';
  static const keyIntervalsIcuAthleteId = 'INTERVALS_ICU_ATHLETE_ID';
  static const keyIntervalsIcuApiKey = 'INTERVALS_ICU_API_KEY';
  static const keyUploadToIntervalsIcu = 'UPLOAD_TO_INTERVALS_ICU';
  static const keyOutbaseSessionId = 'OUTBASE_SESSION_ID';
  static const keyUploadToOutbase = 'UPLOAD_TO_OUTBASE';
  static const keyOutbaseLoginTime = 'OUTBASE_LOGIN_TIME';

  static const allKeys = [
    keyOneLapUsername,
    keyOneLapPassword,
    keyStravaClientId,
    keyStravaClientSecret,
    keyStravaRefreshToken,
    keyStravaAccessToken,
    keyStravaExpiresAt,
    keyStravaUploadMode,
    keyStravaWebCookies,
    keyXingzheUsername,
    keyXingzhePassword,
    keyXingzheSessionId,
    keyLookbackDays,
    keyGcjCorrectionEnabled,
    keyUploadToStrava,
    keyUploadToXingzhe,
    keyIntervalsIcuAthleteId,
    keyIntervalsIcuApiKey,
    keyUploadToIntervalsIcu,
    keyOutbaseSessionId,
    keyUploadToOutbase,
    keyOutbaseLoginTime,
  ];

  Future<Map<String, String>> loadSettings() async {
    final storedValues = await _store.readAll();
    return <String, String>{
      for (final key in allKeys) key: storedValues[key] ?? '',
    };
  }

  Future<void> saveSettings(Map<String, String> values) async {
    for (final entry in values.entries) {
      await _store.write(key: entry.key, value: entry.value);
    }
  }
}
