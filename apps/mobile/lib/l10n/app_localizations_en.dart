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
  String get serverHint => 'https://radius.pi.dev';

  @override
  String get appServerId => 'App Server ID';

  @override
  String get appServerIdHint => '00000000-0000-4000-8000-000000000000';

  @override
  String get validationServerId =>
      'Enter the lowercase UUID shown by the TSPi App Server.';

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
  String get preferences => 'Preferences';

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
  String get connectionDetails => 'Connection details';

  @override
  String get tsPhoneService => 'Pi App Server';

  @override
  String get notConfigured => 'Not configured';

  @override
  String get about => 'About';

  @override
  String clientDescription(String version) {
    return 'Client $version · TSPi mobile companion';
  }

  @override
  String clientVersionBuild(String version, String build) {
    return 'Version $version · Build $build';
  }

  @override
  String get endpoint => 'Pi Radius gateway';

  @override
  String get copyServerAddress => 'Copy server address';

  @override
  String get serverAddressCopied => 'Server address copied';

  @override
  String get copyServerAddressFailed => 'Could not copy server address';

  @override
  String get loadLaterMessages => 'Load later messages';

  @override
  String get problemModelUnavailable =>
      'No model is ready in this TSPi session. Check the model selection on the App Server.';

  @override
  String get problemModelAuthMissing =>
      'The model needs authentication on the Pi App Server. Your TS Phone connection is still valid.';

  @override
  String get problemModelCheckFailed =>
      'The Pi App Server could not verify the model configuration.';

  @override
  String get problemProviderUnavailable =>
      'The model service is temporarily unavailable and this generation failed. You can send again later; tool actions already performed remain recorded.';

  @override
  String get problemProviderRateLimited =>
      'The model service rejected this generation due to rate or quota limits. Try later or check the service quota.';

  @override
  String get problemProviderAuthFailed =>
      'The model service rejected authentication. Check the App Server\'s upstream credentials; this is separate from your phone connection.';

  @override
  String get problemProviderError =>
      'The model service returned an error and this generation failed. Details remain in the App Server\'s session history.';

  @override
  String get problemGenerationIncomplete =>
      'Execution ended without a confirmed complete reply. Review the conversation\'s output and tool results.';

  @override
  String get problemModelStorageUnavailable =>
      'TSPi cannot access its model credentials or cache. Check the App Server\'s Pi directory permissions.';

  @override
  String get problemRuntimeExtensionError =>
      'An extension failed in this TSPi session. Check the latest messages and App Server logs.';

  @override
  String get problemPromptRejected =>
      'Pi rejected this message before model execution. Your draft has been kept.';

  @override
  String get problemDeliveryUncertain =>
      'Message delivery is unconfirmed. Check the latest history before sending again.';

  @override
  String get messageDeliveryUncertain => 'Delivery unconfirmed';

  @override
  String get sessionConfiguredModel => 'Startup model';

  @override
  String get sessionLastModel => 'Last used model';

  @override
  String get auth => 'Auth';

  @override
  String get protocol => 'Protocol';

  @override
  String get latency => 'Latency';

  @override
  String get lastSync => 'Last sync';

  @override
  String get runDiagnostics => 'Check App Server';

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
  String get opening => 'Opening';

  @override
  String get researchDirectoriesRefreshed => 'Research workspaces refreshed';

  @override
  String get noWorkspacesTitle => 'No projects yet';

  @override
  String get noWorkspacesMessage =>
      'Create a project to start a separate TSPi research workspace.';

  @override
  String get workspaces => 'Projects';

  @override
  String get activeItems => 'Current';

  @override
  String get archivedItems => 'Archived';

  @override
  String get recentlyDeleted => 'Recently Deleted';

  @override
  String get newProject => 'New project';

  @override
  String get projectName => 'Project name';

  @override
  String get createProject => 'Create project';

  @override
  String get newSession => 'New session';

  @override
  String get sessionNameOptional => 'Session name (optional)';

  @override
  String get modelOptional => 'Model (optional)';

  @override
  String get createSession => 'Create session';

  @override
  String get manage => 'Manage';

  @override
  String get rename => 'Rename';

  @override
  String get archive => 'Archive';

  @override
  String get restore => 'Restore';

  @override
  String get moveToRecentlyDeleted => 'Move to Recently Deleted';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get startSession => 'Start session';

  @override
  String get startingSession => 'Starting session';

  @override
  String get projectDeleteTitle => 'Delete project?';

  @override
  String get projectDeleteMessage =>
      'This hides the project in Recently Deleted until you restore or permanently delete it.';

  @override
  String get sessionDeleteTitle => 'Delete session?';

  @override
  String get sessionDeleteMessage =>
      'Only this conversation history is moved to Recently Deleted. Scientific project data is not removed.';

  @override
  String get permanentDeleteTitle => 'Delete permanently?';

  @override
  String permanentDeleteMessage(String resourceId) {
    return 'This action cannot be undone. Enter $resourceId to continue.';
  }

  @override
  String get confirmationValue => 'Confirmation';

  @override
  String get deletionBlockedTitle => 'Project cannot be deleted';

  @override
  String get deletionBlockedMessage =>
      'Resolve active workers, remote calculations, approvals, and remote effects first.';

  @override
  String get activeWorkers => 'Active sessions';

  @override
  String get problemManagementChanged =>
      'This project or session has changed. Refresh and try again.';

  @override
  String get problemResourcesBusy =>
      'A session is still active or work remains unresolved. Finish it before continuing.';

  @override
  String get problemPreflightUnavailable =>
      'TSPi could not verify this operation. Check the App Server\'s TSPi configuration and try again.';

  @override
  String get problemManagementUnsupported =>
      'This Pi App Server does not support that operation. Update the App Server runtime; updating the app alone is not enough.';

  @override
  String get appServerVersion => 'App Server version';

  @override
  String get problemManagementCapacity =>
      'Project and session storage is full. Remove unneeded items before adding more.';

  @override
  String get remoteCalculations => 'Remote calculations';

  @override
  String get pendingApprovals => 'Pending approvals';

  @override
  String get unresolvedRemoteEffects => 'Unresolved remote effects';

  @override
  String get archiveEmptyTitle => 'No archived items';

  @override
  String get trashEmptyTitle => 'Recently Deleted is empty';

  @override
  String get archivedItemsMessage =>
      'Archived items stay available here until restored or deleted.';

  @override
  String get recentlyDeletedMessage =>
      'Deleted items can be restored before permanent removal.';

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
  String get noSessionHistoryTitle => 'No sessions yet';

  @override
  String get noSessionHistoryMessage =>
      'Create a session to begin or continue work in this project.';

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
  String get accessController => 'Research';

  @override
  String get accessObserver => 'Read-only Q&A';

  @override
  String get historySession => 'History session';

  @override
  String get historyReadOnlyStatus => 'History · Read-only';

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
  String get sessionRuntimeUnavailable =>
      'No runtime snapshot was saved for this session.';

  @override
  String get copySessionId => 'Copy session ID';

  @override
  String get sessionIdCopied => 'Session ID copied';

  @override
  String get copySessionIdFailed => 'Could not copy session ID';

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
  String get abortTargetChanged =>
      'The active generation changed. Nothing was stopped.';

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
  String get abortGenerationConfirmation =>
      'Stop the current generation? The partial response may be incomplete.';

  @override
  String get keepGenerating => 'Keep generating';

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
  String get composerMessage => 'Message';

  @override
  String get composerReadOnly => 'History is read-only';

  @override
  String get observerMode => 'Read-only observer mode';

  @override
  String get liveSyncConnected => 'Live synchronization connected';

  @override
  String get liveSyncSuspended => 'Live synchronization paused';

  @override
  String get liveSyncClosed => 'Live synchronization closed';

  @override
  String get liveSyncFailed => 'Could not connect to the Pi App Server';

  @override
  String get liveSyncRestoring => 'Restoring live synchronization';

  @override
  String get liveSyncConnecting => 'Connecting to the Pi App Server';

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
  String get timelineFilterAll => 'All';

  @override
  String get timelineFilterMessages => 'Messages';

  @override
  String get timelineFilterActivities => 'Activity';

  @override
  String get timelineFilterEmpty => 'No items in this view';

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
  String get previewImage => 'Preview image';

  @override
  String get loadingImage => 'Loading image';

  @override
  String get imageLoadFailed => 'The image could not be loaded';

  @override
  String get openInBrowser => 'Open in browser';

  @override
  String get settingsLoadFailed =>
      'Could not load settings from this device. Try again.';

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
  String get problemAgentRunChanged =>
      'The active generation changed before it could be stopped';

  @override
  String get problemServiceUnavailable =>
      'The Pi App Server is temporarily unavailable';

  @override
  String get problemConnectionFailed =>
      'Could not connect to the Pi App Server';

  @override
  String get problemRequestTimeout => 'Synchronization timed out. Try again';

  @override
  String get problemRequestFailed => 'The server request failed';

  @override
  String get problemApiRouteMissing =>
      'The requested App Server service is unavailable. Check that the app and Pi runtime are up to date.';

  @override
  String get problemQueueStorage =>
      'The App Server could not confirm request storage. Check its state directory before retrying.';

  @override
  String get problemQueueCapacity =>
      'The App Server request storage is full. Finish pending requests or check its state directory.';

  @override
  String get problemQueueRecovery =>
      'A previous request has an uncertain outcome. Review its history and outputs before continuing.';

  @override
  String get commandQueue => 'Up next';

  @override
  String commandQueueCount(int count) {
    return 'Up next · $count';
  }

  @override
  String get commandQueuePending => 'Messages waiting';

  @override
  String get commandQueueEmpty => 'No messages waiting';

  @override
  String commandQueued(int position) {
    return 'Waiting · $position';
  }

  @override
  String get commandStarting => 'Preparing';

  @override
  String get commandRunning => 'In progress';

  @override
  String get commandCompleted => 'Finished';

  @override
  String get commandFailed => 'Not completed';

  @override
  String get commandUnknown => 'Needs verification';

  @override
  String get commandCancelled => 'Cancelled';

  @override
  String get commandAcknowledged => 'Reviewed';

  @override
  String get cancelQueuedRequest => 'Cancel waiting request';

  @override
  String get acknowledgeRequest => 'Confirm review';

  @override
  String get acknowledgeRequestBody =>
      'Confirm that you have checked this request\'s conversation and outputs. This releases later requests without repeating this one or claiming that it succeeded. Its uncertain runtime must already be stopped.';

  @override
  String get commandWaitingForCurrent => 'Waiting for the current reply';

  @override
  String get commandOtherConversationWaiting =>
      'Another conversation is waiting';

  @override
  String get commandOtherConversation => 'Another conversation';

  @override
  String get commandNeedsReview => 'A previous request needs review';

  @override
  String get modelNextTurn => 'Model for new and waiting messages';

  @override
  String get filterConversations => 'Filter conversations';

  @override
  String get searchConversations => 'Search conversations';

  @override
  String get openSidebar => 'Projects and conversations';

  @override
  String get switchProject => 'Switch project';

  @override
  String get continueSession => 'Continue conversation';

  @override
  String get readOnlyAssistant => 'Read-only Q&A';

  @override
  String get sessionMode => 'Conversation mode';

  @override
  String get workspaceReadOnly => 'Workspace access: read-only';

  @override
  String get workspaceReadWrite => 'Workspace access: read and write';

  @override
  String switchAssistantMode(String mode) {
    return 'Switch to $mode?';
  }

  @override
  String get switchAssistantModeBody =>
      'The idle assistant will restart in this conversation. History and submitted calculations stay intact. If startup fails, you can start the conversation again.';

  @override
  String get activationUpgradeRequired =>
      'Update the Pi App Server to choose a session mode. History remains available.';

  @override
  String get activationWriterActive =>
      'Another process owns this workspace or conversation. Close it on the App Server before continuing. History and drafts are kept.';

  @override
  String get activationInspectionFailed =>
      'The App Server could not complete the session guard check. Check the TSPi installation diagnostics before retrying. History and drafts are kept.';

  @override
  String get activationGuardInvalid =>
      'The App Server could not validate the session history or its writer locks. Inspect the session files on the App Server. Do not delete history or lock files to bypass this check.';

  @override
  String get activationExternalOwner =>
      'This workspace is open in a terminal. Continue that conversation or close it before switching.';

  @override
  String get activationSwitchTitle => 'Continue research in this conversation?';

  @override
  String activationSwitchBody(String name) {
    return 'The idle runtime for $name will stop. Its history and remote calculations are kept. A failed start will not restart it automatically.';
  }

  @override
  String get activationSwitchConfirm => 'Switch';

  @override
  String get activationOpenOwner => 'Open conversation';

  @override
  String get activationFailed =>
      'The conversation did not become ready. Refresh and check the App Server configuration. A runtime stopped during switching will stay offline; history and drafts are kept.';

  @override
  String get activationOutcomeUnknown =>
      'The activation result was not received. The App Server may still be preparing this conversation. Refresh its state before trying again.';

  @override
  String get activationCapacity =>
      'The App Server\'s activation records are full. Wait for active runs to settle, restart the App Server, then refresh.';

  @override
  String get activationRecoveryRequired =>
      'The conversation process could not be confirmed. Inspect it on the App Server before continuing. No message will be resent automatically.';

  @override
  String get preparingSession => 'Preparing conversation';

  @override
  String get localDraft => 'Draft';

  @override
  String get chatWelcome => 'What are we investigating?';

  @override
  String get home => 'Home';

  @override
  String get recentConversations => 'Recent conversations';

  @override
  String get noRecentConversations => 'No recent conversations';

  @override
  String get recentConversationsIncomplete =>
      'Some conversations could not be refreshed';

  @override
  String get unnamedConversation => 'Untitled conversation';

  @override
  String get dataNotProvided => 'Not provided';

  @override
  String get accessPermission => 'Access';

  @override
  String get technicalDetails => 'Technical details';

  @override
  String get messageNoText => 'No displayable response in this record';

  @override
  String get messageNotDisplayed => 'This record has no displayable text';

  @override
  String get messageGenerationFailed => 'Generation failed';

  @override
  String get messageGenerationAborted => 'Generation stopped';

  @override
  String activityRecords(int count) {
    return '$count activity records';
  }

  @override
  String get aboutApp => 'About';

  @override
  String get chooseModel => 'Choose model';

  @override
  String get moreActions => 'More actions';

  @override
  String get searchModels => 'Search models';

  @override
  String get noModelsAvailable => 'No available models';

  @override
  String get appServerDefaultModel => 'App Server default model';

  @override
  String get modelSelectionUnavailable =>
      'Wait for synchronization and pending messages to finish before switching models.';

  @override
  String get modelSelectionBusy =>
      'The assistant is busy. Switch models after this response finishes.';

  @override
  String get modelSelectionAppServerRequired =>
      'Only Pi App Server conversations can switch models here.';

  @override
  String get modelSelectionStartRequired =>
      'Continue this conversation before changing its model.';

  @override
  String get modelPreference => 'Model for the next conversation start';

  @override
  String get viewFullOutput => 'View full output';

  @override
  String get copyOutput => 'Copy full output';

  @override
  String get outputCopied => 'Output copied';

  @override
  String get outputCopyFailed => 'Could not copy output';

  @override
  String get contentDisplayFailed => 'This content could not be displayed.';

  @override
  String activityFailureCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count failed activities',
      one: '1 failed activity',
    );
    return '$_temp0';
  }

  @override
  String viewAllActivities(int count) {
    return 'View all $count activities';
  }

  @override
  String get projectViews => 'Project lists';

  @override
  String get sessionViews => 'Conversation lists';

  @override
  String get archivedProjects => 'Archived projects';

  @override
  String get deletedProjects => 'Recently deleted projects';

  @override
  String get archivedSessions => 'Archived conversations';

  @override
  String get deletedSessions => 'Recently deleted conversations';

  @override
  String get chatReady => 'Ready';

  @override
  String get chatRunning => 'Working';

  @override
  String get chatConnecting => 'Connecting';

  @override
  String get chatReconnecting => 'Reconnecting';

  @override
  String get chatOffline => 'Offline';

  @override
  String get chatRecovery => 'Needs recovery';

  @override
  String get chatFailed => 'Needs attention';

  @override
  String get chatHistory => 'History';

  @override
  String get chatCanContinue => 'Not running';

  @override
  String get activityRead => 'Read file';

  @override
  String get activityWrite => 'Write file';

  @override
  String get activityShell => 'Run command';

  @override
  String get activityState => 'Read workspace';

  @override
  String get activityChange => 'Record research decision';

  @override
  String get activityReview => 'Independent review';

  @override
  String get activityReply => 'Respond to review';

  @override
  String get activityCalculation => 'Calculation';

  @override
  String get activityRemote => 'Remote task';
}
