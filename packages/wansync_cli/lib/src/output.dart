import 'dart:convert';

import 'package:sync_core/sync_core.dart';

/// 人类可读的同步结果文本。
String formatSummaryText(SyncSummary summary) {
  final buf = StringBuffer();
  buf.writeln('OneLap 获取: ${summary.fetched} 个活动');
  buf.writeln('本地判重跳过: ${summary.deduped}');

  if (summary.abortedReason == 'risk-control') {
    buf.writeln('同步中止（OneLap 风控触发）');
    return buf.toString();
  }

  buf.writeln('成功上传: ${summary.success}');
  if (summary.failed > 0) {
    buf.writeln('失败: ${summary.failed}');
  }
  buf.writeln();
  buf.writeln(
    _platformLine(
      'Strava',
      summary.stravaSuccess,
      summary.stravaFailed,
      summary.stravaDeduped,
    ),
  );
  buf.writeln(
    _platformLine(
      'Xingzhe',
      summary.xingzheSuccess,
      summary.xingzheFailed,
      summary.xingzheDeduped,
    ),
  );
  buf.writeln(
    _platformLine(
      'Intervals.icu',
      summary.intervalsIcuSuccess,
      summary.intervalsIcuFailed,
      summary.intervalsIcuDeduped,
    ),
  );
  buf.writeln(
    _platformLine(
      'Outbase',
      summary.outbaseSuccess,
      summary.outbaseFailed,
      summary.outbaseDeduped,
    ),
  );

  final failures = <String>[
    ...summary.stravaFailures.map(
      (f) =>
          'Strava: ${f.displayText}${f.error != null ? ' — ${f.error}' : ''}',
    ),
    ...summary.xingzheFailures.map(
      (f) =>
          'Xingzhe: ${f.displayText}${f.error != null ? ' — ${f.error}' : ''}',
    ),
    ...summary.intervalsIcuFailures.map(
      (f) =>
          'Intervals.icu: ${f.displayText}${f.error != null ? ' — ${f.error}' : ''}',
    ),
    ...summary.outbaseFailures.map(
      (f) =>
          'Outbase: ${f.displayText}${f.error != null ? ' — ${f.error}' : ''}',
    ),
  ];
  if (failures.isNotEmpty) {
    buf.writeln();
    buf.writeln('失败明细:');
    for (final f in failures) {
      buf.writeln('  - $f');
    }
  }
  return buf.toString();
}

String _platformLine(String name, int success, int failed, int deduped) {
  final parts = <String>[];
  if (success + failed + deduped == 0) {
    parts.add('未启用');
  } else {
    parts.add('成功 $success');
    if (failed > 0) parts.add('失败 $failed');
    if (deduped > 0) parts.add('判重 $deduped');
  }
  return '$name: ${parts.join(' | ')}';
}

/// JSON 输出（机器可读）。
String formatSummaryJson(SyncSummary summary) {
  return const JsonEncoder.withIndent('  ').convert({
    'fetched': summary.fetched,
    'deduped': summary.deduped,
    'success': summary.success,
    'failed': summary.failed,
    'abortedReason': summary.abortedReason,
    'failureReasons': summary.failureReasons,
    'platforms': {
      'strava': _platformJson(
        summary.stravaSuccess,
        summary.stravaFailed,
        summary.stravaDeduped,
        summary.stravaFailures,
      ),
      'xingzhe': _platformJson(
        summary.xingzheSuccess,
        summary.xingzheFailed,
        summary.xingzheDeduped,
        summary.xingzheFailures,
      ),
      'intervalsIcu': _platformJson(
        summary.intervalsIcuSuccess,
        summary.intervalsIcuFailed,
        summary.intervalsIcuDeduped,
        summary.intervalsIcuFailures,
      ),
      'outbase': _platformJson(
        summary.outbaseSuccess,
        summary.outbaseFailed,
        summary.outbaseDeduped,
        summary.outbaseFailures,
      ),
    },
    'syncedAt': summary.syncedAt?.toIso8601String(),
  });
}

Map<String, dynamic> _platformJson(
  int success,
  int failed,
  int deduped,
  List<FailedActivitySummary> failures,
) {
  return {
    'success': success,
    'failed': failed,
    'deduped': deduped,
    'failures': failures.map((f) => f.toJson()).toList(),
  };
}
