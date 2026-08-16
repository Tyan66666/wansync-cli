import 'dart:convert';
import 'dart:io';

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
