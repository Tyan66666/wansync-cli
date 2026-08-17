/// 退出码约定：
/// 0 = 同步完成无失败；1 = 同步完成但有失败；2 = 参数错误；
/// 3 = 配置文件无效；4 = 运行时错误。
class ExitCode {
  static const int ok = 0;
  static const int syncFailed = 1;
  static const int usage = 2;
  static const int invalidConfig = 3;
  static const int runtimeError = 4;
}

/// 解析后的 CLI 参数。
class CliOptions {
  final String configPath;
  final int? lookbackDays;
  final List<String>? platforms;
  final bool jsonOutput;
  final String stateDir;
  final bool verbose;

  /// GCJ-02 → WGS-84 坐标转换覆盖开关：
  /// null = 用配置文件 sync.gcjCorrectionEnabled；true/false = 强制开/关。
  final bool? gcjCorrection;

  const CliOptions({
    required this.configPath,
    this.lookbackDays,
    this.platforms,
    this.jsonOutput = false,
    this.stateDir = '',
    this.verbose = false,
    this.gcjCorrection,
  });
}

class UsageException implements Exception {
  final String message;
  const UsageException(this.message);
  @override
  String toString() => message;
}
