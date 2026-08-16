import 'dart:convert';
import 'dart:io';

import 'package:sync_core/sync_core.dart';
import 'package:test/test.dart';

void main() {
  group('MapSettingsStore', () {
    test('read/write/readAll 往返', () async {
      final store = MapSettingsStore();
      await store.write(key: 'a', value: '1');
      await store.write(key: 'b', value: '2');
      expect(await store.read(key: 'a'), '1');
      expect(await store.readAll(), {'a': '1', 'b': '2'});
      expect(await store.read(key: 'missing'), isNull);
    });

    test('可带初始值', () async {
      final store = MapSettingsStore({'k': 'v'});
      expect(await store.read(key: 'k'), 'v');
    });
  });

  group('FileSettingsStore', () {
    late Directory tmp;
    late File file;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wansync-test-');
      file = File('${tmp.path}/settings.json');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('写入后持久化到 JSON 文件，可重新读取', () async {
      final store = FileSettingsStore(file);
      await store.write(key: 'ONELAP_USERNAME', value: 'alice');
      await store.write(key: 'LOOKBACK_DAYS', value: '7');

      final reloaded = FileSettingsStore(file);
      final all = await reloaded.readAll();
      expect(all['ONELAP_USERNAME'], 'alice');
      expect(all['LOOKBACK_DAYS'], '7');
    });

    test('文件不存在时返回空', () async {
      final store = FileSettingsStore(file);
      expect(await store.readAll(), isEmpty);
    });

    test('损坏文件按空配置处理', () async {
      file.writeAsStringSync('{{{not json');
      final store = FileSettingsStore(file);
      expect(await store.readAll(), isEmpty);
    });
  });

  group('SettingsService', () {
    test('loadSettings 补齐所有 key 默认空串', () async {
      final service = SettingsService(store: MapSettingsStore());
      final settings = await service.loadSettings();
      expect(settings.length, SettingsService.allKeys.length);
      expect(settings[SettingsService.keyOneLapUsername], '');
      expect(settings[SettingsService.keyLookbackDays], '');
    });

    test('saveSettings 逐 key 写入', () async {
      final store = MapSettingsStore();
      final service = SettingsService(store: store);
      await service.saveSettings({
        SettingsService.keyOneLapUsername: 'bob',
        SettingsService.keyUploadToStrava: 'true',
      });
      expect(await store.read(key: SettingsService.keyOneLapUsername), 'bob');
    });
  });

  group('ConfigService', () {
    test('settingsFromJson 转换 App 配置段', () {
      final map = ConfigService.settingsFromJson({
        'onelap': {'username': 'u', 'password': 'p'},
        'strava': {'uploadMode': 'api', 'clientId': 'cid'},
        'sync': {
          'lookbackDays': 5,
          'uploadToStrava': true,
          'uploadToXingzhe': false,
        },
      });
      expect(map[SettingsService.keyOneLapUsername], 'u');
      expect(map[SettingsService.keyStravaUploadMode], 'api');
      expect(map[SettingsService.keyLookbackDays], '5');
      expect(map[SettingsService.keyUploadToStrava], 'true');
      expect(map[SettingsService.keyUploadToXingzhe], 'false');
    });

    test('settingsFromJson 缺失段用默认值', () {
      final map = ConfigService.settingsFromJson({});
      expect(map[SettingsService.keyUploadToStrava], 'true');
      expect(map[SettingsService.keyLookbackDays], '3');
      expect(map[SettingsService.keyStravaUploadMode], 'api');
    });

    test('importConfig 校验版本并写入', () async {
      final store = MapSettingsStore();
      final service = ConfigService(
        settingsService: SettingsService(store: store),
      );
      await service.importConfig(
        jsonEncode({
          'version': 1,
          'appVersion': '1.0.0',
          'exportedAt': '2026-01-01',
          'settings': {
            'onelap': {'username': 'alice', 'password': 'secret'},
          },
        }),
      );
      expect(await store.read(key: SettingsService.keyOneLapUsername), 'alice');
    });

    test('importConfig 不支持的版本抛 FormatException', () {
      final service = ConfigService(
        settingsService: SettingsService(store: MapSettingsStore()),
      );
      expect(
        () => service.importConfig(jsonEncode({'version': 99})),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('StateStore 注入', () {
    test('注入 stateFile 后可落盘判重', () async {
      final tmp = Directory.systemTemp.createTempSync('wansync-state-');
      final file = File('${tmp.path}/state.json');
      final store = StateStore(stateFile: file);

      await store.markPlatformSynced('fp1', 'strava', 101);
      expect(await store.isAlreadyUploaded('fp1', 'strava'), isTrue);
      expect(await store.getRemoteActivityId('fp1', 'strava'), 101);

      // 重新加载同一文件，状态仍在
      final reloaded = StateStore(stateFile: file);
      expect(await reloaded.isAlreadyUploaded('fp1', 'strava'), isTrue);
      tmp.deleteSync(recursive: true);
    });
  });

  group('SyncEngine 注入', () {
    test('构造接受注入的 downloadDir 与 stateStore', () {
      final engine = SyncEngine(
        oneLapClient: OneLapClient(
          baseUrl: 'https://example.com',
          username: 'u',
          password: 'p',
        ),
        stravaClient: null,
        stateStore: StateStore(),
        downloadDir: Directory.systemTemp,
      );
      expect(engine.downloadDir.path, Directory.systemTemp.path);
      expect(engine.downloadConcurrency, 3);
    });
  });
}
