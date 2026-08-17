import 'dart:convert';
import 'dart:io';

import 'package:json5/json5.dart';
import 'package:sync_core/sync_core.dart';

import 'cli_options.dart';

class InvalidConfigException implements Exception {
  final String message;
  const InvalidConfigException(this.message);
  @override
  String toString() => message;
}

/// GCJ-02 → WGS-84 坐标转换开关解析：
/// CLI 显式指定（--gcj-correction / --no-gcj-correction）优先，否则用配置值。
bool resolveGcjCorrection(bool? cliValue, bool configValue) {
  return cliValue ?? configValue;
}

/// 读取配置文件 JSON 并校验（AppConfig.fromJson 自带版本校验）。
/// 支持 JSONC：配置可带 `//` 与 `/* */` 注释（json5 解析）。
AppConfig loadConfig(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw InvalidConfigException('配置文件不存在: $path');
  }
  final String content;
  try {
    content = file.readAsStringSync();
  } catch (e) {
    throw InvalidConfigException('读取配置文件失败: $e');
  }
  final Map<String, dynamic> json;
  try {
    json = json5Decode(content) as Map<String, dynamic>;
  } catch (_) {
    throw const InvalidConfigException(
      '配置文件格式无效：不是合法 JSON（支持 // 与 /* */ 注释）',
    );
  }
  try {
    return AppConfig.fromJson(json);
  } on FormatException catch (e) {
    throw InvalidConfigException(e.message);
  }
}

/// 在 JSONC 原文中定位 `"section": {` 起始位置后的指定键，把字符串值替换为新值。
/// 返回替换后的完整文本；section 或键不存在时返回 null（调用方回退全量重写）。
/// 用于 token / sessionId 回写时保留用户写的注释与格式。
String? replaceStringValueInSection(
  String source,
  String sectionKey,
  String key,
  String newValue,
) {
  final sectionMatch =
      RegExp('"${RegExp.escape(sectionKey)}"\\s*:\\s*\\{').firstMatch(source);
  if (sectionMatch == null) return null;
  final sectionBody = source.substring(sectionMatch.end);
  final keyPattern = RegExp('"${RegExp.escape(key)}"\\s*:\\s*"([^"]*)"');
  final keyMatch = keyPattern.firstMatch(sectionBody);
  if (keyMatch == null) return null;
  final absStart = sectionMatch.end + keyMatch.start;
  return source.replaceRange(absStart, sectionMatch.end + keyMatch.end,
      '"$key": "$newValue"');
}

/// 把 strava 段的新 token 回写到 --config 指向的 JSON 文件（原地更新，保留注释）。
Future<void> writeBackStravaTokens(
  String configPath,
  AppConfig config, {
  required String accessToken,
  required String refreshToken,
  required int expiresAt,
}) async {
  final File file = File(configPath);
  var source = '';
  try {
    source = file.readAsStringSync();
  } catch (_) {
    // 读取失败按空文本处理，回退全量重写
  }
  var updated = source;
  var allReplaced = true;
  for (final entry in {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': '$expiresAt',
  }.entries) {
    final next = replaceStringValueInSection(
        updated, 'strava', entry.key, entry.value);
    if (next == null) {
      allReplaced = false;
      break;
    }
    updated = next;
  }
  if (allReplaced) {
    // 原文精准替换成功：注释与其余格式原样保留
    await file.writeAsString(updated);
    return;
  }

  // 键不存在（用户配置文件缺字段）：回退全量重写
  final settings = config.settings;
  final strava = _castMap(settings['strava']);
  strava['accessToken'] = accessToken;
  strava['refreshToken'] = refreshToken;
  strava['expiresAt'] = '$expiresAt';
  settings['strava'] = strava;

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(config.toJson()),
  );
}

Map<String, dynamic> _castMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

/// 从配置装配 SyncEngine 并执行一次同步。
Future<SyncSummary> runSync(CliOptions options, AppConfig config) async {
  final settings = ConfigService.settingsFromJson(config.settings);

  String get(String key) => settings[key] ?? '';

  // 平台开关（配置 + --platform 覆盖）
  bool uploadToStrava = get(SettingsService.keyUploadToStrava) != 'false';
  bool uploadToXingzhe = get(SettingsService.keyUploadToXingzhe) == 'true';
  bool uploadToIntervalsIcu =
      get(SettingsService.keyUploadToIntervalsIcu) == 'true';
  bool uploadToOutbase = get(SettingsService.keyUploadToOutbase) == 'true';

  if (options.platforms != null) {
    final enabled = options.platforms!.toSet();
    uploadToStrava = enabled.contains('strava');
    uploadToXingzhe = enabled.contains('xingzhe');
    uploadToIntervalsIcu = enabled.contains('intervalsIcu');
    uploadToOutbase = enabled.contains('outbase');
  }

  // 目录
  final stateFile = File('${options.stateDir}/state.json');
  final downloadDir = Directory('${options.stateDir}/fit_downloads');

  // === 配置校验（先于任何网络调用，配置错立即报错） ===
  if (get(SettingsService.keyOneLapUsername).isEmpty) {
    throw const InvalidConfigException('配置缺少 OneLap 账号（onelap.username）');
  }
  if (uploadToStrava && get(SettingsService.keyStravaUploadMode) == 'web') {
    throw const InvalidConfigException(
      '配置中 Strava 为 web 模式，CLI 仅支持 API 模式（请在 App 中重新导出）',
    );
  }

  // OneLap（必用：数据源）
  final oneLap = OneLapClient(
    baseUrl: 'https://www.onelap.cn',
    username: get(SettingsService.keyOneLapUsername),
    password: get(SettingsService.keyOneLapPassword),
  );
  await oneLap.login();

  // Strava（仅 API 模式）
  StravaClient? strava;
  if (uploadToStrava) {
    strava = StravaClient(
      clientId: get(SettingsService.keyStravaClientId),
      clientSecret: get(SettingsService.keyStravaClientSecret),
      refreshToken: get(SettingsService.keyStravaRefreshToken),
      accessToken: get(SettingsService.keyStravaAccessToken),
      expiresAt: int.tryParse(get(SettingsService.keyStravaExpiresAt)) ?? 0,
      onTokenRefreshed:
          ({
            required String accessToken,
            required String refreshToken,
            required int expiresAt,
          }) {
            return writeBackStravaTokens(
              options.configPath,
              config,
              accessToken: accessToken,
              refreshToken: refreshToken,
              expiresAt: expiresAt,
            );
          },
    );
  }

  // Xingzhe
  XingzheClient? xingzhe;
  if (uploadToXingzhe) {
    xingzhe = XingzheClient.create(
      username: get(SettingsService.keyXingzheUsername),
      password: get(SettingsService.keyXingzhePassword),
      sessionId: get(SettingsService.keyXingzheSessionId),
      onSessionPersist: (sessionId) async {
        // 回写 xingzhe.sessionId 到配置文件（精准替换，保留注释）
        final configFile = File(options.configPath);
        final source = configFile.existsSync()
            ? configFile.readAsStringSync()
            : '';
        final updated = replaceStringValueInSection(
            source, 'xingzhe', 'sessionId', sessionId);
        if (updated != null) {
          await configFile.writeAsString(updated);
        } else {
          final settingsMap = config.settings;
          final xz = _castMap(settingsMap['xingzhe']);
          xz['sessionId'] = sessionId;
          settingsMap['xingzhe'] = xz;
          await configFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert(config.toJson()),
          );
        }
      },
    );
  }

  // Intervals.icu
  IntervalsIcuClient? intervalsIcu;
  if (uploadToIntervalsIcu) {
    intervalsIcu = IntervalsIcuClient(
      athleteId: get(SettingsService.keyIntervalsIcuAthleteId),
      apiKey: get(SettingsService.keyIntervalsIcuApiKey),
    );
  }

  // Outbase
  OutbaseClient? outbase;
  if (uploadToOutbase) {
    outbase = OutbaseClient(
      sessionId: get(SettingsService.keyOutbaseSessionId),
    );
  }

  final stateStore = StateStore(stateFile: stateFile);
  final rewriteService = FitCoordinateRewriteService(
    loadCacheDirectory: () async => downloadDir,
  );

  final engine = SyncEngine(
    oneLapClient: oneLap,
    stravaClient: strava,
    xingzheClient: xingzhe,
    intervalsIcuClient: intervalsIcu,
    outbaseClient: outbase,
    stateStore: stateStore,
    gcjCorrectionEnabled: resolveGcjCorrection(
      options.gcjCorrection,
      get(SettingsService.keyGcjCorrectionEnabled) == 'true',
    ),
    rewriteService: rewriteService,
    uploadToStrava: uploadToStrava,
    uploadToXingzhe: uploadToXingzhe,
    uploadToIntervalsIcu: uploadToIntervalsIcu,
    uploadToOutbase: uploadToOutbase,
    downloadDir: downloadDir,
  );

  return engine.runOnce(
    lookbackDays:
        options.lookbackDays ??
        int.tryParse(get(SettingsService.keyLookbackDays)) ??
        3,
  );
}
