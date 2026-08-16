import 'dart:io';

import 'package:wansync_cli/src/args.dart';
import 'package:wansync_cli/src/cli_options.dart';
import 'package:wansync_cli/src/output.dart';
import 'package:wansync_cli/src/runner.dart';

Future<void> main(List<String> args) async {
  final CliOptions options;
  try {
    final parsed = parseArgs(args);
    if (parsed == null) {
      exit(ExitCode.ok); // help / version 已输出
    }
    options = parsed;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(ExitCode.usage);
  }

  try {
    final config = loadConfig(options.configPath);

    if (options.verbose) {
      stderr.writeln('配置已加载: ${options.configPath}');
      stderr.writeln('状态目录: ${options.stateDir}');
    }

    final summary = await runSync(options, config);

    if (options.jsonOutput) {
      stdout.writeln(formatSummaryJson(summary));
    } else {
      stdout.writeln(formatSummaryText(summary));
    }

    exit(summary.failed > 0 ? ExitCode.syncFailed : ExitCode.ok);
  } on InvalidConfigException catch (e) {
    stderr.writeln('配置无效: ${e.message}');
    exit(ExitCode.invalidConfig);
  } catch (e) {
    stderr.writeln('运行时错误: $e');
    exit(ExitCode.runtimeError);
  }
}
