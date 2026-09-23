import 'app_localizations.dart';

extension HostMonitorLocalizations on AppLocalizations {
  bool get _monitorChinese => localeName.startsWith('zh');
  String get hostMonitors => _monitorChinese ? '任务监控' : 'Task monitors';
  String get hostMonitorsEmpty => _monitorChinese
      ? '提交计算任务后，监控会显示在这里。'
      : 'Monitors appear here after a computation is submitted.';
  String get hostMonitorEnabled =>
      _monitorChinese ? '监控已启用' : 'Monitoring enabled';
  String get hostMonitorDisabled =>
      _monitorChinese ? '监控已暂停' : 'Monitoring paused';
  String hostMonitorPending(int count) =>
      _monitorChinese ? '$count 条通知待处理' : '$count pending notifications';
  String hostMonitorObserved(String time) =>
      _monitorChinese ? '上次检查：$time' : 'Last checked: $time';
  String hostMonitorState(String state) => switch (state) {
    'running' => _monitorChinese ? '运行中' : 'Running',
    'queued' || 'pending' => _monitorChinese ? '排队中' : 'Queued',
    'completed' ||
    'succeeded' ||
    'success' => _monitorChinese ? '已完成' : 'Completed',
    'failed' || 'error' => _monitorChinese ? '失败' : 'Failed',
    'cancelled' || 'canceled' => _monitorChinese ? '已取消' : 'Cancelled',
    'unknown' => _monitorChinese ? '等待首次检查' : 'Waiting for the first check',
    _ => state,
  };
}
