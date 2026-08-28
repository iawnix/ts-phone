// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'TS Phone';

  @override
  String get back => '返回';

  @override
  String get settings => '设置';

  @override
  String get connectionSettings => '连接设置';

  @override
  String get connectTsPhone => '连接 TS Phone';

  @override
  String get mobileCompanion => 'TSPi 移动终端';

  @override
  String get server => '服务器';

  @override
  String get serverHint => 'https://tsphone.example.com';

  @override
  String get accessToken => '访问令牌';

  @override
  String get showToken => '显示令牌';

  @override
  String get hideToken => '隐藏令牌';

  @override
  String get connect => '连接';

  @override
  String get connecting => '正在连接';

  @override
  String get validationCompleteServerAddress => '请输入完整的服务器地址';

  @override
  String get validationNoUrlComponents => '服务器地址不能包含账号、查询参数或片段';

  @override
  String get validationOriginOnly => '服务器地址只能填写域名和端口';

  @override
  String get validationHttpsRequired => '远程服务器必须使用 HTTPS';

  @override
  String get validationTokenInvalid => '访问令牌格式无效';

  @override
  String get appearance => '外观';

  @override
  String get themeSystem => '系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get saveAppearanceFailed => '无法保存外观设置';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get saveLanguageFailed => '无法保存语言设置';

  @override
  String get connection => '连接';

  @override
  String get tsPhoneService => 'TS Phone 服务';

  @override
  String get notConfigured => '尚未配置';

  @override
  String get about => '关于';

  @override
  String clientDescription(String version) {
    return '客户端 $version · TSPi 移动终端';
  }

  @override
  String get endpoint => 'Endpoint';

  @override
  String get auth => '认证';

  @override
  String get protocol => '协议';

  @override
  String get latency => '延迟';

  @override
  String get lastSync => '上次同步';

  @override
  String get runDiagnostics => '运行连接诊断';

  @override
  String get diagnosticsRunning => '正在诊断连接';

  @override
  String get diagnosticConfigured => '已配置';

  @override
  String get diagnosticVerified => '已验证';

  @override
  String get diagnosticFailed => '失败';

  @override
  String get diagnosticNotChecked => '未检测';

  @override
  String get client => 'Client';

  @override
  String get build => 'Build';

  @override
  String get refresh => '刷新';

  @override
  String get refreshing => '正在刷新';

  @override
  String get researchDirectoriesRefreshed => '研究目录已刷新';

  @override
  String get noWorkspacesTitle => '没有可用研究目录';

  @override
  String get noWorkspacesMessage => '请检查 TS Phone 服务端的工作区配置。';

  @override
  String get workspaces => '工作区';

  @override
  String liveSessionCount(int count) {
    return '$count 个在线会话';
  }

  @override
  String get noLiveSessions => '没有在线会话';

  @override
  String get statusConnected => '已连接';

  @override
  String get statusReady => '就绪';

  @override
  String get statusRunning => '运行中';

  @override
  String get statusConnecting => '连接中';

  @override
  String get statusOffline => '离线';

  @override
  String get statusRecovery => '待恢复';

  @override
  String get statusError => '错误';

  @override
  String statusLive(int count) {
    return '$count 在线';
  }

  @override
  String workspaceStateStale(String problem) {
    return '$problem，目录状态可能已过期';
  }

  @override
  String get loadWorkspacesFailed => '无法载入研究目录';

  @override
  String get retry => '重试';

  @override
  String get startCommandCopied => '启动命令已复制';

  @override
  String get refreshSessions => '刷新会话';

  @override
  String get noSessionHistoryTitle => '没有会话历史';

  @override
  String get noSessionHistoryMessage => '在电脑端启动该工作区的 TSPi 后，会话历史会显示在这里。';

  @override
  String get copyStartCommand => '复制启动命令';

  @override
  String sessionStateStale(String problem) {
    return '$problem，会话状态可能已过期';
  }

  @override
  String get sessions => '会话';

  @override
  String sessionCount(int count) {
    return '$count 个会话';
  }

  @override
  String controllerSessionCount(int count) {
    return '$count 个主会话';
  }

  @override
  String get loadSessionsFailed => '无法载入会话';

  @override
  String get runtimeOffline => 'TSPi 未启动';

  @override
  String get runtimeConnecting => '正在连接 TSPi';

  @override
  String get runtimeIdle => '已连接 · 可发送';

  @override
  String get runtimeRunning => '正在生成';

  @override
  String get runtimeRecoveryRequired => '会话需要恢复';

  @override
  String get runtimeCompactOffline => '离线';

  @override
  String get runtimeCompactConnecting => '连接中';

  @override
  String get runtimeCompactReady => '就绪';

  @override
  String get runtimeCompactRunning => '生成中';

  @override
  String get runtimeCompactRecovery => '待恢复';

  @override
  String get accessController => '主会话';

  @override
  String get accessObserver => '只读会话';

  @override
  String get historySession => '历史会话';

  @override
  String sessionFallback(String shortId) {
    return '会话 $shortId';
  }

  @override
  String sessionToken(String shortId) {
    return 'session $shortId';
  }

  @override
  String get messagesSynced => '消息已同步';

  @override
  String get abortRequested => '已发送中止请求';

  @override
  String get approvalTitle => '需要你的确认';

  @override
  String get approvalRequestDescription => 'TSPi 请求执行以下受控操作。';

  @override
  String get approvalWorkspace => '工作区';

  @override
  String get approvalSession => '会话';

  @override
  String get approvalTool => '工具';

  @override
  String get approvalDetails => '操作详情';

  @override
  String approvalExpiresIn(int seconds) {
    return '$seconds 秒后过期';
  }

  @override
  String approvalQueueRemaining(int count) {
    return '还有 $count 个请求等待处理';
  }

  @override
  String get approvalApproving => '正在批准';

  @override
  String get approvalRejecting => '正在拒绝';

  @override
  String get approvalExpired => '该授权请求已过期';

  @override
  String get approvalStale => '该授权属于旧会话，已失效';

  @override
  String get approvalMissing => '该授权已处理或不再可用';

  @override
  String get reject => '拒绝';

  @override
  String get approveOnce => '仅批准本次';

  @override
  String get syncing => '正在同步';

  @override
  String get syncMessages => '同步消息';

  @override
  String get noMessages => '当前会话没有消息';

  @override
  String get jumpToStart => '回到会话开始';

  @override
  String get jumpToLatest => '回到最新消息';

  @override
  String get sending => '正在发送';

  @override
  String get send => '发送';

  @override
  String get aborting => '正在中止';

  @override
  String get abortGeneration => '中止生成';

  @override
  String get composerSynchronizing => '正在同步...';

  @override
  String get composerOffline => 'TSPi 离线';

  @override
  String get composerHistory => '只读历史';

  @override
  String get composerRecovery => '需要恢复会话';

  @override
  String get composerReconnecting => '正在重连...';

  @override
  String get composerMessage => '输入指令或问题...';

  @override
  String get observerMode => '只读观察模式';

  @override
  String get liveSyncConnected => '实时同步已连接';

  @override
  String get liveSyncSuspended => '实时同步已暂停';

  @override
  String get liveSyncClosed => '实时同步已关闭';

  @override
  String get liveSyncFailed => '无法连接 TS Phone 服务';

  @override
  String get liveSyncRestoring => '正在恢复实时同步';

  @override
  String get liveSyncConnecting => '正在连接 TS Phone 服务';

  @override
  String get generationDisconnectedBanner =>
      '生成过程中连接中断。请先在电脑端核对最后一条消息，系统不会自动重发。';

  @override
  String get tspiDisconnectedBanner => 'TSPi 已断开，重新启动后将自动恢复。';

  @override
  String get reconnect => '重新连接';

  @override
  String get tspiNotStartedTitle => 'TSPi 尚未启动';

  @override
  String get tspiNotStartedDescription => '在电脑端运行以下命令后，本页会自动连接。';

  @override
  String get waitingForTspi => '正在等待 TSPi';

  @override
  String get generationDisconnectedTitle => '生成过程中连接中断';

  @override
  String get generationDisconnectedDescription =>
      '系统不会自动重发最后一条提示。请先在电脑端核对 TSPi 会话。';

  @override
  String get waitingForRecovery => '正在等待会话恢复';

  @override
  String get checkAgain => '重新检测';

  @override
  String get sessionSynchronizingTitle => '正在同步会话';

  @override
  String get sessionSynchronizingMessage => '正在读取当前会话状态和消息。';

  @override
  String get liveSyncInterrupted => '实时同步中断';

  @override
  String get reconnecting => '正在重连';

  @override
  String get you => '你';

  @override
  String get messageOriginPhone => '手机';

  @override
  String get messageOriginCli => 'CLI';

  @override
  String get messageSending => '正在发送';

  @override
  String get messageSynchronizing => '正在等待实时同步';

  @override
  String get tspiGenerating => 'TSPi · 正在生成';

  @override
  String get toolResult => '工具结果';

  @override
  String toolRunning(String name) {
    return '正在运行 $name';
  }

  @override
  String get toolRunningGeneric => '正在运行工具';

  @override
  String get toolFailed => '工具执行失败';

  @override
  String get invalidMessage => '收到一个无法解析的消息';

  @override
  String get invalidApproval => '收到一个无法解析的权限请求';

  @override
  String get invalidHistoryMessage => '收到一个当前客户端无法解析的历史消息。';

  @override
  String get loadEarlierMessages => '加载更早消息';

  @override
  String get loadingEarlierMessages => '正在加载更早消息';

  @override
  String get networkRetrying => '网络连接中断，正在重试';

  @override
  String imageAlt(String alt) {
    return '[图片：$alt]';
  }

  @override
  String get blockedNonHttpsImage => '[已阻止非 HTTPS 图片]';

  @override
  String openImageWithAlt(String alt) {
    return '在浏览器中打开图片：$alt';
  }

  @override
  String get openImage => '在浏览器中打开图片';

  @override
  String get problemIncompatible => '服务器数据格式与当前 App 不兼容';

  @override
  String get problemAuthentication => '认证失败，请检查访问令牌';

  @override
  String get problemSessionOffline => 'TSPi 会话已断开';

  @override
  String get problemSessionChanged => '会话已变化，请重新同步';

  @override
  String get problemServiceUnavailable => 'TS Phone 服务暂时不可用';

  @override
  String get problemConnectionFailed => '无法连接 TS Phone 服务';

  @override
  String get problemRequestTimeout => '同步超时，请重试';

  @override
  String get problemRequestFailed => '服务器请求失败';
}
