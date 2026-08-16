import 'dart:io';

import 'package:args/args.dart';

import 'cli_options.dart';

/// 解析命令行参数。返回 null 表示应显示 help/version 后退出 0。
CliOptions? parseArgs(List<String> args) {
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', help: 'App 导出的配置文件 JSON 路径（必填）')
    ..addOption('lookback', help: '向后回看天数（覆盖配置内 lookbackDays）')
    ..addOption(
      'platform',
      help: '仅同步的平台，逗号分隔：strava,xingzhe,intervalsIcu,outbase',
    )
    ..addFlag('json', help: '以 JSON 输出结果', negatable: false)
    ..addOption('state-dir', help: 'state.json 与临时目录位置（默认 ~/.wansync）')
    ..addFlag('verbose', abbr: 'v', help: '详细输出', negatable: false)
    ..addFlag('help', abbr: 'h', help: '显示帮助', negatable: false)
    ..addFlag('version', help: '显示版本', negatable: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    throw UsageException('参数错误: ${e.message}\n\n${usageText(parser)}');
  }

  if (parsed['help'] as bool) {
    stdout.writeln(usageText(parser));
    return null;
  }
  if (parsed['version'] as bool) {
    stdout.writeln('wansync 0.1.0');
    return null;
  }

  final configPath = parsed['config'] as String?;
  if (configPath == null || configPath.isEmpty) {
    throw UsageException('缺少 --config 参数（App 导出的配置文件路径）');
  }

  int? lookbackDays;
  final lookback = parsed['lookback'] as String?;
  if (lookback != null) {
    lookbackDays = int.tryParse(lookback);
    if (lookbackDays == null || lookbackDays < 0) {
      throw const UsageException('--lookback 必须是 >= 0 的整数');
    }
  }

  List<String>? platforms;
  final platform = parsed['platform'] as String?;
  if (platform != null) {
    platforms = platform
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    const allowed = {'strava', 'xingzhe', 'intervalsIcu', 'outbase'};
    for (final p in platforms) {
      if (!allowed.contains(p)) {
        throw UsageException(
          '--platform 含未知平台: $p（可选: strava,xingzhe,intervalsIcu,outbase）',
        );
      }
    }
  }

  final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
  final stateDir = (parsed['state-dir'] as String?)?.isNotEmpty == true
      ? parsed['state-dir'] as String
      : '$home/.wansync';

  return CliOptions(
    configPath: configPath,
    lookbackDays: lookbackDays,
    platforms: platforms,
    jsonOutput: parsed['json'] as bool,
    stateDir: stateDir,
    verbose: parsed['verbose'] as bool,
  );
}

String usageText(ArgParser parser) {
  return '''
用法: wansync sync [选项]

从 App 导出的配置 JSON 读取凭据，同步 OneLap 活动到各平台。

${parser.usage}

示例:
  wansync sync --config app-config.json
  wansync sync -c app-config.json --lookback 7 --platform strava,xingzhe
  wansync sync -c app-config.json --json
''';
}
