import 'dart:convert';
import 'dart:io';

import 'package:json5/json5.dart';
import 'package:sync_core/sync_core.dart';
import 'package:test/test.dart';
import 'package:wansync_cli/src/args.dart';
import 'package:wansync_cli/src/cli_options.dart';
import 'package:wansync_cli/src/output.dart';
import 'package:wansync_cli/src/runner.dart';

void main() {
  group('parseArgs', () {
    test('完整参数', () {
      final opts = parseArgs([
        'sync',
        '--config',
        'app.json',
        '--lookback',
        '7',
        '--platform',
        'strava,xingzhe',
        '--json',
        '--state-dir',
        '/tmp/ws',
        '--verbose',
      ])!;
      expect(opts.configPath, 'app.json');
      expect(opts.lookbackDays, 7);
      expect(opts.platforms, ['strava', 'xingzhe']);
      expect(opts.jsonOutput, isTrue);
      expect(opts.stateDir, '/tmp/ws');
      expect(opts.verbose, isTrue);
    });

    test('缺 config 抛 UsageException', () {
      expect(() => parseArgs(['sync']), throwsA(isA<UsageException>()));
    });

    test('lookback 非整数抛 UsageException', () {
      expect(
        () => parseArgs(['sync', '--config', 'a.json', '--lookback', 'x']),
        throwsA(isA<UsageException>()),
      );
    });

    test('未知 platform 抛 UsageException', () {
      expect(
        () => parseArgs(['sync', '--config', 'a.json', '--platform', 'nike']),
        throwsA(isA<UsageException>()),
      );
    });

    test('help 返回 null 且不抛', () {
      expect(parseArgs(['--help']), isNull);
      expect(parseArgs(['--version']), isNull);
    });

    test('默认 state-dir 用 HOME', () {
      final opts = parseArgs(['sync', '--config', 'a.json'])!;
      final home = Platform.environment['HOME']!;
      expect(opts.stateDir, '$home/.wansync');
    });

    test('gcj-correction 三态：不传为 null', () {
      final opts = parseArgs(['sync', '--config', 'a.json'])!;
      expect(opts.gcjCorrection, isNull);
    });

    test('gcj-correction 三态：--gcj-correction 为 true', () {
      final opts = parseArgs([
        'sync',
        '--config',
        'a.json',
        '--gcj-correction',
      ])!;
      expect(opts.gcjCorrection, isTrue);
    });

    test('gcj-correction 三态：--no-gcj-correction 为 false', () {
      final opts = parseArgs([
        'sync',
        '--config',
        'a.json',
        '--no-gcj-correction',
      ])!;
      expect(opts.gcjCorrection, isFalse);
    });
  });

  group('loadConfig', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('wansync-cli-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    File write(String name, String content) {
      final f = File('${tmp.path}/$name');
      f.writeAsStringSync(content);
      return f;
    }

    test('合法配置解析成功', () {
      final f = write(
        'ok.json',
        jsonEncode({
          'version': 1,
          'appVersion': '1.0.0',
          'exportedAt': '2026-01-01',
          'settings': {
            'onelap': {'username': 'u', 'password': 'p'},
          },
        }),
      );
      final config = loadConfig(f.path);
      expect(config.version, 1);
      expect(config.settings['onelap']['username'], 'u');
    });

    test('文件不存在抛 InvalidConfigException', () {
      expect(
        () => loadConfig('${tmp.path}/missing.json'),
        throwsA(isA<InvalidConfigException>()),
      );
    });

    test('非法 JSON 抛 InvalidConfigException', () {
      final f = write('bad.json', 'not json');
      expect(() => loadConfig(f.path), throwsA(isA<InvalidConfigException>()));
    });

    test('版本不支持抛 InvalidConfigException', () {
      final f = write('old.json', jsonEncode({'version': 99}));
      expect(
        () => loadConfig(f.path),
        throwsA(
          predicate(
            (e) => e is InvalidConfigException && e.message.contains('不受支持'),
          ),
        ),
      );
    });

    test('JSONC：行注释与块注释可解析', () {
      final f = write(
        'commented.json',
        '''
{
  // 行注释
  "version": 1, /* 块注释 */
  "appVersion": "1.0.0",
  "settings": {
    "onelap": { "username": "u", "password": "p" }, // 行尾注释
    "strava": {
      "uploadMode": "api",
      // 字符串内 // 不应被当作注释
      "clientSecret": "https://example.com/a//b"
    }
  }
}
''',
      );
      final config = loadConfig(f.path);
      expect(config.version, 1);
      expect(config.settings['onelap']['username'], 'u');
      final strava = config.settings['strava'] as Map<String, dynamic>;
      expect(strava['clientSecret'], 'https://example.com/a//b');
    });

    test('JSONC：URL 与转义引号不被注释逻辑误伤', () {
      final f = write(
        'url.json',
        r'''
{
  "version": 1,
  "settings": {
    "onelap": { "username": "a\"b", "password": "https://x.com/p" },
    "sync": { "lookbackDays": 3 }
  }
}
''',
      );
      final config = loadConfig(f.path);
      final onelap = config.settings['onelap'] as Map<String, dynamic>;
      expect(onelap['username'], 'a"b');
      expect(onelap['password'], 'https://x.com/p');
    });
  });

  group('resolveGcjCorrection', () {
    test('CLI 未指定时用配置值', () {
      expect(resolveGcjCorrection(null, true), isTrue);
      expect(resolveGcjCorrection(null, false), isFalse);
    });

    test('CLI 强制开启覆盖配置关闭', () {
      expect(resolveGcjCorrection(true, false), isTrue);
    });

    test('CLI 强制关闭覆盖配置开启', () {
      expect(resolveGcjCorrection(false, true), isFalse);
    });
  });

  group('runSync 配置校验先于网络', () {
    late Directory tmp;

    setUp(
      () => tmp = Directory.systemTemp.createTempSync('wansync-preflight-'),
    );
    tearDown(() => tmp.deleteSync(recursive: true));

    CliOptions opts(String config) =>
        CliOptions(configPath: config, stateDir: tmp.path);

    test('缺 OneLap 账号：抛 InvalidConfigException，不发网络请求', () async {
      final f = File('${tmp.path}/nouser.json');
      f.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'settings': {
            'sync': {'uploadToStrava': true},
          },
        }),
      );
      final config = loadConfig(f.path);
      expect(
        () => runSync(opts(f.path), config),
        throwsA(
          predicate(
            (e) => e is InvalidConfigException && e.message.contains('OneLap'),
          ),
        ),
      );
    });

    test('Strava web 模式：抛 InvalidConfigException，不发网络请求', () async {
      final f = File('${tmp.path}/web.json');
      f.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'settings': {
            'onelap': {'username': 'u', 'password': 'p'},
            'strava': {'uploadMode': 'web'},
            'sync': {'uploadToStrava': true},
          },
        }),
      );
      final config = loadConfig(f.path);
      expect(
        () => runSync(opts(f.path), config),
        throwsA(
          predicate(
            (e) => e is InvalidConfigException && e.message.contains('web 模式'),
          ),
        ),
      );
    });
  });

  group('writeBackStravaTokens', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('wansync-token-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('原地更新 strava 段三个字段', () async {
      final f = File('${tmp.path}/config.json');
      f.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'appVersion': '1.0.0',
          'exportedAt': '2026-01-01',
          'settings': {
            'strava': {
              'uploadMode': 'api',
              'clientId': 'cid',
              'accessToken': 'old',
              'refreshToken': 'oldr',
              'expiresAt': '0',
            },
          },
        }),
      );
      final config = loadConfig(f.path);

      await writeBackStravaTokens(
        f.path,
        config,
        accessToken: 'new',
        refreshToken: 'newr',
        expiresAt: 9999999999,
      );

      final reloaded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final strava = reloaded['settings']['strava'] as Map<String, dynamic>;
      expect(strava['accessToken'], 'new');
      expect(strava['refreshToken'], 'newr');
      expect(strava['expiresAt'], '9999999999');
      expect(strava['clientId'], 'cid'); // 其余字段保留
    });

    test('带注释的配置：回写后注释保留', () async {
      final f = File('${tmp.path}/commented.json');
      f.writeAsStringSync(
        '''
{
  "version": 1, // 版本注释
  "appVersion": "1.0.0",
  "settings": {
    "strava": { // strava 段
      "uploadMode": "api",
      "accessToken": "old", // 旧 token
      "refreshToken": "oldr",
      "expiresAt": "0"
    }
  }
}
''',
      );
      final config = loadConfig(f.path);

      await writeBackStravaTokens(
        f.path,
        config,
        accessToken: 'new',
        refreshToken: 'newr',
        expiresAt: 9999999999,
      );

      final raw = f.readAsStringSync();
      // 注释还在
      expect(raw, contains('// 版本注释'));
      expect(raw, contains('// strava 段'));
      expect(raw, contains('// 旧 token'));
      // 值已更新
      expect(raw, contains('"accessToken": "new"'));
      expect(raw, contains('"refreshToken": "newr"'));
      expect(raw, contains('"expiresAt": "9999999999"'));
      // 仍是合法 JSONC
      final reloaded =
          json5Decode(raw) as Map<String, dynamic>;
      final strava = reloaded['settings']['strava'] as Map<String, dynamic>;
      expect(strava['accessToken'], 'new');
    });

    test('缺失键时回退全量重写（无注释场景）', () async {
      final f = File('${tmp.path}/noexpires.json');
      f.writeAsStringSync(
        jsonEncode({
          'version': 1,
          'appVersion': '1.0.0',
          'exportedAt': '2026-01-01',
          'settings': {
            'strava': {'uploadMode': 'api', 'accessToken': 'old'},
          },
        }),
      );
      final config = loadConfig(f.path);

      await writeBackStravaTokens(
        f.path,
        config,
        accessToken: 'new',
        refreshToken: 'newr',
        expiresAt: 9999999999,
      );

      final reloaded = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final strava = reloaded['settings']['strava'] as Map<String, dynamic>;
      expect(strava['accessToken'], 'new');
      expect(strava['refreshToken'], 'newr');
      expect(strava['expiresAt'], '9999999999');
    });
  });

  group('formatSummary', () {
    const summary = SyncSummary(
      fetched: 5,
      deduped: 2,
      success: 3,
      failed: 1,
      failureReasons: ['x'],
      stravaSuccess: 3,
      stravaFailed: 0,
      stravaDeduped: 2,
      xingzheSuccess: 0,
      xingzheFailed: 0,
      xingzheDeduped: 0,
    );

    test('文本输出包含统计', () {
      final text = formatSummaryText(summary);
      expect(text, contains('OneLap 获取: 5'));
      expect(text, contains('本地判重跳过: 2'));
      expect(text, contains('成功上传: 3'));
      expect(text, contains('Strava: 成功 3 | 判重 2'));
      expect(text, contains('Xingzhe: 未启用'));
    });

    test('JSON 输出结构完整', () {
      final json =
          jsonDecode(formatSummaryJson(summary)) as Map<String, dynamic>;
      expect(json['fetched'], 5);
      expect(json['success'], 3);
      expect(json['failed'], 1);
      final strava = json['platforms']['strava'] as Map<String, dynamic>;
      expect(strava['success'], 3);
      expect(strava['deduped'], 2);
    });

    test('风控中止文本', () {
      const aborted = SyncSummary(
        fetched: 0,
        deduped: 0,
        success: 0,
        failed: 0,
        abortedReason: 'risk-control',
      );
      expect(formatSummaryText(aborted), contains('风控'));
    });
  });

  group('CliOptions 与退出码', () {
    test('退出码常量', () {
      expect(ExitCode.ok, 0);
      expect(ExitCode.syncFailed, 1);
      expect(ExitCode.usage, 2);
      expect(ExitCode.invalidConfig, 3);
      expect(ExitCode.runtimeError, 4);
    });
  });
}
