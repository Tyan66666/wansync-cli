import '../models/sync_summary.dart';

class SyncFailureFormatter {
  static final RegExp _failurePattern = RegExp(
    r'^(下载失败|上传失败|坐标转换失败) \((.+?)\):\s*(.*)$',
  );
  static const String _downloadFitShareHint =
      '可以试试先从 OneLap/顽鹿导出 FIT，再分享到顽爪爪进行同步。';

  static String toUserMessage(String raw) {
    final Match? match = _failurePattern.firstMatch(raw.trim());
    if (match == null) return '同步失败：请稍后重试。';

    final String kind = match.group(1)!;
    final String filename = match.group(2)!;
    final String detail = (match.group(3) ?? '').toLowerCase();

    if (kind == '下载失败') {
      if (detail.contains('http 404')) {
        return '下载失败（$filename）：OneLap 源文件可能已过期或已删除，请在顽鹿 App 内确认该活动是否仍可导出。$_downloadFitShareHint';
      }
      if (detail.contains('timeout') || detail.contains('timed out')) {
        return '下载失败（$filename）：OneLap 下载超时，请检查网络后重试。$_downloadFitShareHint';
      }
      return '下载失败（$filename）：OneLap 文件下载失败，请稍后重试。$_downloadFitShareHint';
    }

    if (kind == '坐标转换失败') {
      return '坐标转换失败（$filename）：FIT 文件在上传前转换失败，请稍后重试。';
    }

    if (detail.contains('5xx') ||
        detail.contains('http 5') ||
        detail.contains('503')) {
      return '上传失败（$filename）：Strava 服务暂时不可用，请稍后重试。';
    }
    if (detail.contains('401') || detail.contains('403')) {
      return '上传失败（$filename）：Strava 授权可能已失效，请在设置中重新授权后重试。';
    }
    return '上传失败（$filename）：Strava 上传失败，请稍后重试。';
  }

  static String buildClipboardText(SyncSummary summary) {
    return buildClipboardTextWithMeta(summary: summary);
  }

  static String buildClipboardTextWithMeta({
    required SyncSummary summary,
    String? appVersion,
    DateTime? generatedAt,
  }) {
    final DateTime timestamp = generatedAt ?? DateTime.now().toUtc();
    final List<String> lines = <String>[
      'WanSync 同步失败详细信息',
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'app_version=${appVersion.trim()}',
      'generated_at_utc=${timestamp.toIso8601String()}',
      'fetched=${summary.fetched}, deduped=${summary.deduped}, success=${summary.success}, failed=${summary.failed}',
      'failure_reasons:',
    ];

    for (var i = 0; i < summary.failureReasons.length; i++) {
      lines.add('${i + 1}. ${summary.failureReasons[i]}');
    }
    return lines.join('\n');
  }
}
