// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TS Phone';

  @override
  String get back => 'Back';

  @override
  String get settings => 'Settings';

  @override
  String get connectionSettings => 'Connection settings';

  @override
  String get connectTsPhone => 'Connect to TS Phone';

  @override
  String get mobileCompanion => 'TSPi mobile companion';

  @override
  String get server => 'Server';

  @override
  String get serverHint => 'https://tsphone.example.com';

  @override
  String get accessToken => 'Access token';

  @override
  String get showToken => 'Show token';

  @override
  String get hideToken => 'Hide token';

  @override
  String get connect => 'Connect';

  @override
  String get connecting => 'Connecting';

  @override
  String get validationCompleteServerAddress =>
      'Enter a complete server address';

  @override
  String get validationNoUrlComponents =>
      'The server address cannot include credentials, query parameters, or fragments';

  @override
  String get validationOriginOnly => 'Enter only the server domain and port';

  @override
  String get validationHttpsRequired => 'Remote servers must use HTTPS';

  @override
  String get validationTokenInvalid => 'The access token format is invalid';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get saveAppearanceFailed => 'Could not save the appearance setting';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languageEnglish => 'English';

  @override
  String get saveLanguageFailed => 'Could not save the language setting';

  @override
  String get connection => 'Connection';

  @override
  String get tsPhoneService => 'TS Phone service';

  @override
  String get notConfigured => 'Not configured';

  @override
  String get about => 'About';

  @override
  String clientDescription(String version) {
    return 'Client $version · TSPi mobile companion';
  }

  @override
  String get endpoint => 'Endpoint';

  @override
  String get auth => 'Auth';

  @override
  String get protocol => 'Protocol';

  @override
  String get latency => 'Latency';

  @override
  String get lastSync => 'Last sync';

  @override
  String get runDiagnostics => 'Check Phone service';

  @override
  String get diagnosticsRunning => 'Checking';

  @override
  String get diagnosticConfigured => 'Configured';

  @override
  String get diagnosticVerified => 'Healthy';

  @override
  String get diagnosticFailed => 'Issue';

  @override
  String get diagnosticNotChecked => 'Not checked';

  @override
  String get client => 'Client';

  @override
  String get build => 'Build';

  @override
  String get refresh => 'Refresh';

  @override
  String get refreshing => 'Refreshing';

  @override
  String get researchDirectoriesRefreshed => 'Research workspaces refreshed';

  @override
  String get noWorkspacesTitle => 'No research workspaces';

  @override
  String get noWorkspacesMessage =>
      'Check the workspace configuration on the TS Phone server.';

  @override
  String get workspaces => 'Workspaces';

  @override
  String liveSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count live sessions',
      one: '1 live session',
    );
    return '$_temp0';
  }

  @override
  String get noLiveSessions => 'No live sessions';

  @override
  String get statusConnected => 'CONNECTED';

  @override
  String get statusReady => 'READY';

  @override
  String get statusRunning => 'RUNNING';

  @override
  String get statusConnecting => 'CONNECTING';

  @override
  String get statusOffline => 'OFFLINE';

  @override
  String get statusRecovery => 'RECOVER';

  @override
  String get statusError => 'ERROR';

  @override
  String statusLive(int count) {
    return '$count LIVE';
  }

  @override
  String workspaceStateStale(String problem) {
    return '$problem. Workspace status may be outdated.';
  }

  @override
  String get loadWorkspacesFailed => 'Could not load research workspaces';

  @override
  String get retry => 'Retry';

  @override
  String get startCommandCopied => 'Start command copied';

  @override
  String get refreshSessions => 'Refresh sessions';

  @override
  String get noSessionHistoryTitle => 'No session history';

  @override
  String get noSessionHistoryMessage =>
      'Start TSPi for this workspace on your computer. Its session history will appear here.';

  @override
  String get copyStartCommand => 'Copy start command';

  @override
  String sessionStateStale(String problem) {
    return '$problem. Session status may be outdated.';
  }

  @override
  String get sessions => 'Sessions';

  @override
  String sessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String controllerSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count controllers',
      one: '1 controller',
    );
    return '$_temp0';
  }

  @override
  String get loadSessionsFailed => 'Could not load sessions';

  @override
  String get runtimeOffline => 'TSPi not running';

  @override
  String get runtimeConnecting => 'Connecting to TSPi';

  @override
  String get runtimeIdle => 'Connected · Ready';

  @override
  String get runtimeRunning => 'Generating';

  @override
  String get runtimeRecoveryRequired => 'Session recovery required';

  @override
  String get runtimeCompactOffline => 'Offline';

  @override
  String get runtimeCompactConnecting => 'Connecting';

  @override
  String get runtimeCompactReady => 'Ready';

  @override
  String get runtimeCompactRunning => 'Generating';

  @override
  String get runtimeCompactRecovery => 'Recover';

  @override
  String get accessController => 'Controller';

  @override
  String get accessObserver => 'Read-only session';

  @override
  String get historySession => 'History session';

  @override
  String sessionFallback(String shortId) {
    return 'Session $shortId';
  }

  @override
  String sessionToken(String shortId) {
    return 'session $shortId';
  }

  @override
  String get sessionRuntimeTapHint => 'View session details';

  @override
  String get sessionRuntimeDetails => 'Session details';

  @override
  String get sessionRuntimeLastKnown =>
      'TSPi is offline. These are the last known runtime values.';

  @override
  String get sessionModel => 'Model';

  @override
  String get sessionProvider => 'Provider';

  @override
  String get sessionContextWindow => 'Context';

  @override
  String get sessionContextRemaining => 'Remaining';

  @override
  String get sessionContextSource => 'Measurement';

  @override
  String get sessionContextEstimate => 'Pi estimate';

  @override
  String get sessionContextUnavailable => 'Not available';

  @override
  String get sessionRuntimeUpdated => 'Updated';

  @override
  String get messagesSynced => 'Messages synchronized';

  @override
  String get abortRequested => 'Abort request sent';

  @override
  String get approvalTitle => 'Confirmation required';

  @override
  String get approvalRequestDescription =>
      'TSPi is requesting permission for this controlled action.';

  @override
  String get approvalWorkspace => 'Workspace';

  @override
  String get approvalSession => 'Session';

  @override
  String get approvalTool => 'Tool';

  @override
  String get approvalDetails => 'Action details';

  @override
  String approvalExpiresIn(int seconds) {
    return 'Expires in ${seconds}s';
  }

  @override
  String approvalQueueRemaining(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more requests are waiting',
      one: '1 more request is waiting',
    );
    return '$_temp0';
  }

  @override
  String get approvalApproving => 'Approving';

  @override
  String get approvalRejecting => 'Rejecting';

  @override
  String get approvalExpired => 'This approval request has expired';

  @override
  String get approvalStale =>
      'This approval belongs to an earlier session and is no longer valid';

  @override
  String get approvalMissing =>
      'This approval was already handled or is no longer available';

  @override
  String get reject => 'Reject';

  @override
  String get approveOnce => 'Approve once';

  @override
  String get syncing => 'Synchronizing';

  @override
  String get syncMessages => 'Synchronize messages';

  @override
  String get noMessages => 'No messages in this session';

  @override
  String get jumpToStart => 'Jump to the start of the session';

  @override
  String get jumpToLatest => 'Jump to latest message';

  @override
  String get sending => 'Sending';

  @override
  String get send => 'Send';

  @override
  String get aborting => 'Aborting';

  @override
  String get abortGeneration => 'Stop generation';

  @override
  String get composerSynchronizing => 'Syncing...';

  @override
  String get composerOffline => 'TSPi is offline';

  @override
  String get composerHistory => 'Read-only history';

  @override
  String get composerRecovery => 'Recovery required';

  @override
  String get composerReconnecting => 'Reconnecting...';

  @override
  String get composerMessage => 'Ask or instruct session...';

  @override
  String get observerMode => 'Read-only observer mode';

  @override
  String get liveSyncConnected => 'Live synchronization connected';

  @override
  String get liveSyncSuspended => 'Live synchronization paused';

  @override
  String get liveSyncClosed => 'Live synchronization closed';

  @override
  String get liveSyncFailed => 'Could not connect to the TS Phone service';

  @override
  String get liveSyncRestoring => 'Restoring live synchronization';

  @override
  String get liveSyncConnecting => 'Connecting to the TS Phone service';

  @override
  String get generationDisconnectedBanner =>
      'The connection was interrupted during generation. Check the last message on your computer first; it will not be resent automatically.';

  @override
  String get tspiDisconnectedBanner =>
      'TSPi disconnected. Synchronization will resume after it restarts.';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get tspiNotStartedTitle => 'TSPi has not started';

  @override
  String get tspiNotStartedDescription =>
      'Run this command on your computer. This page will connect automatically.';

  @override
  String get waitingForTspi => 'Waiting for TSPi';

  @override
  String get generationDisconnectedTitle =>
      'Connection interrupted during generation';

  @override
  String get generationDisconnectedDescription =>
      'The last prompt will not be resent automatically. Check the TSPi session on your computer first.';

  @override
  String get waitingForRecovery => 'Waiting for session recovery';

  @override
  String get checkAgain => 'Check again';

  @override
  String get sessionSynchronizingTitle => 'Synchronizing session';

  @override
  String get sessionSynchronizingMessage =>
      'Reading the current session state and messages.';

  @override
  String get liveSyncInterrupted => 'Live synchronization interrupted';

  @override
  String get reconnecting => 'Reconnecting';

  @override
  String get you => 'You';

  @override
  String get messageOriginPhone => 'Phone';

  @override
  String get messageOriginCli => 'CLI';

  @override
  String get messageSending => 'Sending';

  @override
  String get messageSynchronizing => 'Waiting for live sync';

  @override
  String get tspiGenerating => 'TSPi · Generating';

  @override
  String get toolResult => 'Tool result';

  @override
  String toolRunning(String name) {
    return 'Running $name';
  }

  @override
  String get toolRunningGeneric => 'Running tool';

  @override
  String get toolFailed => 'Tool failed';

  @override
  String get invalidMessage => 'Received a message this client could not read';

  @override
  String get invalidApproval =>
      'Received an approval request this client could not read';

  @override
  String get invalidHistoryMessage =>
      'A historical message could not be read by this client.';

  @override
  String get loadEarlierMessages => 'Load earlier messages';

  @override
  String get loadingEarlierMessages => 'Loading earlier messages';

  @override
  String get loadAllHistory => 'Load all history';

  @override
  String get loadingAllHistory => 'Loading all history';

  @override
  String timelineProgress(int loaded, int total) {
    return '$loaded / $total items';
  }

  @override
  String timelineTurns(int count) {
    return '$count turns';
  }

  @override
  String timelineActivities(int count) {
    return '$count activities';
  }

  @override
  String get timelineBranches => 'Session branches';

  @override
  String get timelineActiveBranch => 'Active branch';

  @override
  String timelineBranchLabel(String shortId) {
    return 'Branch $shortId';
  }

  @override
  String timelineTurnLabel(int number) {
    return 'Turn $number';
  }

  @override
  String get timelineSubagent => 'Subagent';

  @override
  String get timelineResearch => 'Research';

  @override
  String get timelineReview => 'Review';

  @override
  String get timelineWorkspace => 'Workspace';

  @override
  String get timelineConfiguration => 'Configuration';

  @override
  String get timelineModelChange => 'Model changed';

  @override
  String get timelineThinkingLevelChange => 'Thinking level changed';

  @override
  String get timelineSessionInfo => 'Session information';

  @override
  String get timelineContext => 'Context';

  @override
  String get timelineSystem => 'System';

  @override
  String get timelineCompleted => 'Completed';

  @override
  String get timelineFailed => 'Failed';

  @override
  String get timelineRecorded => 'Recorded';

  @override
  String get timelineStage => 'Stage';

  @override
  String get timelineNodes => 'Research nodes';

  @override
  String get timelineReference => 'Reference';

  @override
  String get timelineRetrySafe => 'Safe to retry';

  @override
  String get timelineRetryUnsafe => 'Do not retry automatically';

  @override
  String timelineDuration(String seconds) {
    return '${seconds}s';
  }

  @override
  String timelineTokens(int count) {
    return '$count tokens';
  }

  @override
  String get composerHistoricalBranch => 'Read-only historical branch';

  @override
  String get networkRetrying => 'Network connection interrupted. Retrying';

  @override
  String imageAlt(String alt) {
    return '[Image: $alt]';
  }

  @override
  String get blockedNonHttpsImage => '[Blocked a non-HTTPS image]';

  @override
  String openImageWithAlt(String alt) {
    return 'Open image in browser: $alt';
  }

  @override
  String get openImage => 'Open image in browser';

  @override
  String get problemIncompatible =>
      'The server data is incompatible with this app';

  @override
  String get problemAuthentication =>
      'Authentication failed. Check the access token';

  @override
  String get problemSessionOffline => 'The TSPi session is offline';

  @override
  String get problemSessionChanged => 'The session changed. Synchronize again';

  @override
  String get problemServiceUnavailable =>
      'The TS Phone service is temporarily unavailable';

  @override
  String get problemConnectionFailed =>
      'Could not connect to the TS Phone service';

  @override
  String get problemRequestTimeout => 'Synchronization timed out. Try again';

  @override
  String get problemRequestFailed => 'The server request failed';
}
