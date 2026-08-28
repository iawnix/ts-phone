import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'TS Phone'**
  String get appTitle;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @connectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Connection settings'**
  String get connectionSettings;

  /// No description provided for @connectTsPhone.
  ///
  /// In en, this message translates to:
  /// **'Connect to TS Phone'**
  String get connectTsPhone;

  /// No description provided for @mobileCompanion.
  ///
  /// In en, this message translates to:
  /// **'TSPi mobile companion'**
  String get mobileCompanion;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @serverHint.
  ///
  /// In en, this message translates to:
  /// **'https://tsphone.example.com'**
  String get serverHint;

  /// No description provided for @accessToken.
  ///
  /// In en, this message translates to:
  /// **'Access token'**
  String get accessToken;

  /// No description provided for @showToken.
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get showToken;

  /// No description provided for @hideToken.
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get hideToken;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get connecting;

  /// No description provided for @validationCompleteServerAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter a complete server address'**
  String get validationCompleteServerAddress;

  /// No description provided for @validationNoUrlComponents.
  ///
  /// In en, this message translates to:
  /// **'The server address cannot include credentials, query parameters, or fragments'**
  String get validationNoUrlComponents;

  /// No description provided for @validationOriginOnly.
  ///
  /// In en, this message translates to:
  /// **'Enter only the server domain and port'**
  String get validationOriginOnly;

  /// No description provided for @validationHttpsRequired.
  ///
  /// In en, this message translates to:
  /// **'Remote servers must use HTTPS'**
  String get validationHttpsRequired;

  /// No description provided for @validationTokenInvalid.
  ///
  /// In en, this message translates to:
  /// **'The access token format is invalid'**
  String get validationTokenInvalid;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @saveAppearanceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the appearance setting'**
  String get saveAppearanceFailed;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @saveLanguageFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the language setting'**
  String get saveLanguageFailed;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @tsPhoneService.
  ///
  /// In en, this message translates to:
  /// **'TS Phone service'**
  String get tsPhoneService;

  /// No description provided for @notConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get notConfigured;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @clientDescription.
  ///
  /// In en, this message translates to:
  /// **'Client {version} · TSPi mobile companion'**
  String clientDescription(String version);

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get endpoint;

  /// No description provided for @auth.
  ///
  /// In en, this message translates to:
  /// **'Auth'**
  String get auth;

  /// No description provided for @protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get protocol;

  /// No description provided for @latency.
  ///
  /// In en, this message translates to:
  /// **'Latency'**
  String get latency;

  /// No description provided for @lastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync'**
  String get lastSync;

  /// No description provided for @runDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Run connection diagnostics'**
  String get runDiagnostics;

  /// No description provided for @diagnosticsRunning.
  ///
  /// In en, this message translates to:
  /// **'Running connection diagnostics'**
  String get diagnosticsRunning;

  /// No description provided for @diagnosticConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get diagnosticConfigured;

  /// No description provided for @diagnosticVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get diagnosticVerified;

  /// No description provided for @diagnosticFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get diagnosticFailed;

  /// No description provided for @diagnosticNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get diagnosticNotChecked;

  /// No description provided for @client.
  ///
  /// In en, this message translates to:
  /// **'Client'**
  String get client;

  /// No description provided for @build.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get build;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @refreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing'**
  String get refreshing;

  /// No description provided for @researchDirectoriesRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Research workspaces refreshed'**
  String get researchDirectoriesRefreshed;

  /// No description provided for @noWorkspacesTitle.
  ///
  /// In en, this message translates to:
  /// **'No research workspaces'**
  String get noWorkspacesTitle;

  /// No description provided for @noWorkspacesMessage.
  ///
  /// In en, this message translates to:
  /// **'Check the workspace configuration on the TS Phone server.'**
  String get noWorkspacesMessage;

  /// No description provided for @workspaces.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspaces;

  /// No description provided for @liveSessionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 live session} other{{count} live sessions}}'**
  String liveSessionCount(int count);

  /// No description provided for @noLiveSessions.
  ///
  /// In en, this message translates to:
  /// **'No live sessions'**
  String get noLiveSessions;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED'**
  String get statusConnected;

  /// No description provided for @statusReady.
  ///
  /// In en, this message translates to:
  /// **'READY'**
  String get statusReady;

  /// No description provided for @statusRunning.
  ///
  /// In en, this message translates to:
  /// **'RUNNING'**
  String get statusRunning;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'CONNECTING'**
  String get statusConnecting;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get statusOffline;

  /// No description provided for @statusRecovery.
  ///
  /// In en, this message translates to:
  /// **'RECOVER'**
  String get statusRecovery;

  /// No description provided for @statusError.
  ///
  /// In en, this message translates to:
  /// **'ERROR'**
  String get statusError;

  /// No description provided for @statusLive.
  ///
  /// In en, this message translates to:
  /// **'{count} LIVE'**
  String statusLive(int count);

  /// No description provided for @workspaceStateStale.
  ///
  /// In en, this message translates to:
  /// **'{problem}. Workspace status may be outdated.'**
  String workspaceStateStale(String problem);

  /// No description provided for @loadWorkspacesFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load research workspaces'**
  String get loadWorkspacesFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @startCommandCopied.
  ///
  /// In en, this message translates to:
  /// **'Start command copied'**
  String get startCommandCopied;

  /// No description provided for @refreshSessions.
  ///
  /// In en, this message translates to:
  /// **'Refresh sessions'**
  String get refreshSessions;

  /// No description provided for @noSessionHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'No session history'**
  String get noSessionHistoryTitle;

  /// No description provided for @noSessionHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Start TSPi for this workspace on your computer. Its session history will appear here.'**
  String get noSessionHistoryMessage;

  /// No description provided for @copyStartCommand.
  ///
  /// In en, this message translates to:
  /// **'Copy start command'**
  String get copyStartCommand;

  /// No description provided for @sessionStateStale.
  ///
  /// In en, this message translates to:
  /// **'{problem}. Session status may be outdated.'**
  String sessionStateStale(String problem);

  /// No description provided for @sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessions;

  /// No description provided for @sessionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String sessionCount(int count);

  /// No description provided for @controllerSessionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 controller} other{{count} controllers}}'**
  String controllerSessionCount(int count);

  /// No description provided for @loadSessionsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load sessions'**
  String get loadSessionsFailed;

  /// No description provided for @runtimeOffline.
  ///
  /// In en, this message translates to:
  /// **'TSPi not running'**
  String get runtimeOffline;

  /// No description provided for @runtimeConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to TSPi'**
  String get runtimeConnecting;

  /// No description provided for @runtimeIdle.
  ///
  /// In en, this message translates to:
  /// **'Connected · Ready'**
  String get runtimeIdle;

  /// No description provided for @runtimeRunning.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get runtimeRunning;

  /// No description provided for @runtimeRecoveryRequired.
  ///
  /// In en, this message translates to:
  /// **'Session recovery required'**
  String get runtimeRecoveryRequired;

  /// No description provided for @runtimeCompactOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get runtimeCompactOffline;

  /// No description provided for @runtimeCompactConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get runtimeCompactConnecting;

  /// No description provided for @runtimeCompactReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get runtimeCompactReady;

  /// No description provided for @runtimeCompactRunning.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get runtimeCompactRunning;

  /// No description provided for @runtimeCompactRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get runtimeCompactRecovery;

  /// No description provided for @accessController.
  ///
  /// In en, this message translates to:
  /// **'Controller'**
  String get accessController;

  /// No description provided for @accessObserver.
  ///
  /// In en, this message translates to:
  /// **'Read-only session'**
  String get accessObserver;

  /// No description provided for @historySession.
  ///
  /// In en, this message translates to:
  /// **'History session'**
  String get historySession;

  /// No description provided for @sessionFallback.
  ///
  /// In en, this message translates to:
  /// **'Session {shortId}'**
  String sessionFallback(String shortId);

  /// No description provided for @sessionToken.
  ///
  /// In en, this message translates to:
  /// **'session {shortId}'**
  String sessionToken(String shortId);

  /// No description provided for @messagesSynced.
  ///
  /// In en, this message translates to:
  /// **'Messages synchronized'**
  String get messagesSynced;

  /// No description provided for @abortRequested.
  ///
  /// In en, this message translates to:
  /// **'Abort request sent'**
  String get abortRequested;

  /// No description provided for @approvalTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirmation required'**
  String get approvalTitle;

  /// No description provided for @approvalRequestDescription.
  ///
  /// In en, this message translates to:
  /// **'TSPi is requesting permission for this controlled action.'**
  String get approvalRequestDescription;

  /// No description provided for @approvalWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get approvalWorkspace;

  /// No description provided for @approvalSession.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get approvalSession;

  /// No description provided for @approvalTool.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get approvalTool;

  /// No description provided for @approvalDetails.
  ///
  /// In en, this message translates to:
  /// **'Action details'**
  String get approvalDetails;

  /// No description provided for @approvalExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {seconds}s'**
  String approvalExpiresIn(int seconds);

  /// No description provided for @approvalQueueRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more request is waiting} other{{count} more requests are waiting}}'**
  String approvalQueueRemaining(int count);

  /// No description provided for @approvalApproving.
  ///
  /// In en, this message translates to:
  /// **'Approving'**
  String get approvalApproving;

  /// No description provided for @approvalRejecting.
  ///
  /// In en, this message translates to:
  /// **'Rejecting'**
  String get approvalRejecting;

  /// No description provided for @approvalExpired.
  ///
  /// In en, this message translates to:
  /// **'This approval request has expired'**
  String get approvalExpired;

  /// No description provided for @approvalStale.
  ///
  /// In en, this message translates to:
  /// **'This approval belongs to an earlier session and is no longer valid'**
  String get approvalStale;

  /// No description provided for @approvalMissing.
  ///
  /// In en, this message translates to:
  /// **'This approval was already handled or is no longer available'**
  String get approvalMissing;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @approveOnce.
  ///
  /// In en, this message translates to:
  /// **'Approve once'**
  String get approveOnce;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing'**
  String get syncing;

  /// No description provided for @syncMessages.
  ///
  /// In en, this message translates to:
  /// **'Synchronize messages'**
  String get syncMessages;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages in this session'**
  String get noMessages;

  /// No description provided for @jumpToStart.
  ///
  /// In en, this message translates to:
  /// **'Jump to the start of the session'**
  String get jumpToStart;

  /// No description provided for @jumpToLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest message'**
  String get jumpToLatest;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get sending;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @aborting.
  ///
  /// In en, this message translates to:
  /// **'Aborting'**
  String get aborting;

  /// No description provided for @abortGeneration.
  ///
  /// In en, this message translates to:
  /// **'Stop generation'**
  String get abortGeneration;

  /// No description provided for @composerSynchronizing.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get composerSynchronizing;

  /// No description provided for @composerOffline.
  ///
  /// In en, this message translates to:
  /// **'TSPi is offline'**
  String get composerOffline;

  /// No description provided for @composerHistory.
  ///
  /// In en, this message translates to:
  /// **'Read-only history'**
  String get composerHistory;

  /// No description provided for @composerRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery required'**
  String get composerRecovery;

  /// No description provided for @composerReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get composerReconnecting;

  /// No description provided for @composerMessage.
  ///
  /// In en, this message translates to:
  /// **'Ask or instruct session...'**
  String get composerMessage;

  /// No description provided for @observerMode.
  ///
  /// In en, this message translates to:
  /// **'Read-only observer mode'**
  String get observerMode;

  /// No description provided for @liveSyncConnected.
  ///
  /// In en, this message translates to:
  /// **'Live synchronization connected'**
  String get liveSyncConnected;

  /// No description provided for @liveSyncSuspended.
  ///
  /// In en, this message translates to:
  /// **'Live synchronization paused'**
  String get liveSyncSuspended;

  /// No description provided for @liveSyncClosed.
  ///
  /// In en, this message translates to:
  /// **'Live synchronization closed'**
  String get liveSyncClosed;

  /// No description provided for @liveSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the TS Phone service'**
  String get liveSyncFailed;

  /// No description provided for @liveSyncRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring live synchronization'**
  String get liveSyncRestoring;

  /// No description provided for @liveSyncConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the TS Phone service'**
  String get liveSyncConnecting;

  /// No description provided for @generationDisconnectedBanner.
  ///
  /// In en, this message translates to:
  /// **'The connection was interrupted during generation. Check the last message on your computer first; it will not be resent automatically.'**
  String get generationDisconnectedBanner;

  /// No description provided for @tspiDisconnectedBanner.
  ///
  /// In en, this message translates to:
  /// **'TSPi disconnected. Synchronization will resume after it restarts.'**
  String get tspiDisconnectedBanner;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @tspiNotStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'TSPi has not started'**
  String get tspiNotStartedTitle;

  /// No description provided for @tspiNotStartedDescription.
  ///
  /// In en, this message translates to:
  /// **'Run this command on your computer. This page will connect automatically.'**
  String get tspiNotStartedDescription;

  /// No description provided for @waitingForTspi.
  ///
  /// In en, this message translates to:
  /// **'Waiting for TSPi'**
  String get waitingForTspi;

  /// No description provided for @generationDisconnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection interrupted during generation'**
  String get generationDisconnectedTitle;

  /// No description provided for @generationDisconnectedDescription.
  ///
  /// In en, this message translates to:
  /// **'The last prompt will not be resent automatically. Check the TSPi session on your computer first.'**
  String get generationDisconnectedDescription;

  /// No description provided for @waitingForRecovery.
  ///
  /// In en, this message translates to:
  /// **'Waiting for session recovery'**
  String get waitingForRecovery;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @sessionSynchronizingTitle.
  ///
  /// In en, this message translates to:
  /// **'Synchronizing session'**
  String get sessionSynchronizingTitle;

  /// No description provided for @sessionSynchronizingMessage.
  ///
  /// In en, this message translates to:
  /// **'Reading the current session state and messages.'**
  String get sessionSynchronizingMessage;

  /// No description provided for @liveSyncInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Live synchronization interrupted'**
  String get liveSyncInterrupted;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get reconnecting;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @messageOriginPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get messageOriginPhone;

  /// No description provided for @messageOriginCli.
  ///
  /// In en, this message translates to:
  /// **'CLI'**
  String get messageOriginCli;

  /// No description provided for @messageSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get messageSending;

  /// No description provided for @messageSynchronizing.
  ///
  /// In en, this message translates to:
  /// **'Waiting for live sync'**
  String get messageSynchronizing;

  /// No description provided for @tspiGenerating.
  ///
  /// In en, this message translates to:
  /// **'TSPi · Generating'**
  String get tspiGenerating;

  /// No description provided for @toolResult.
  ///
  /// In en, this message translates to:
  /// **'Tool result'**
  String get toolResult;

  /// No description provided for @toolRunning.
  ///
  /// In en, this message translates to:
  /// **'Running {name}'**
  String toolRunning(String name);

  /// No description provided for @toolRunningGeneric.
  ///
  /// In en, this message translates to:
  /// **'Running tool'**
  String get toolRunningGeneric;

  /// No description provided for @toolFailed.
  ///
  /// In en, this message translates to:
  /// **'Tool failed'**
  String get toolFailed;

  /// No description provided for @invalidMessage.
  ///
  /// In en, this message translates to:
  /// **'Received a message this client could not read'**
  String get invalidMessage;

  /// No description provided for @invalidApproval.
  ///
  /// In en, this message translates to:
  /// **'Received an approval request this client could not read'**
  String get invalidApproval;

  /// No description provided for @invalidHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'A historical message could not be read by this client.'**
  String get invalidHistoryMessage;

  /// No description provided for @loadEarlierMessages.
  ///
  /// In en, this message translates to:
  /// **'Load earlier messages'**
  String get loadEarlierMessages;

  /// No description provided for @loadingEarlierMessages.
  ///
  /// In en, this message translates to:
  /// **'Loading earlier messages'**
  String get loadingEarlierMessages;

  /// No description provided for @networkRetrying.
  ///
  /// In en, this message translates to:
  /// **'Network connection interrupted. Retrying'**
  String get networkRetrying;

  /// No description provided for @imageAlt.
  ///
  /// In en, this message translates to:
  /// **'[Image: {alt}]'**
  String imageAlt(String alt);

  /// No description provided for @blockedNonHttpsImage.
  ///
  /// In en, this message translates to:
  /// **'[Blocked a non-HTTPS image]'**
  String get blockedNonHttpsImage;

  /// No description provided for @openImageWithAlt.
  ///
  /// In en, this message translates to:
  /// **'Open image in browser: {alt}'**
  String openImageWithAlt(String alt);

  /// No description provided for @openImage.
  ///
  /// In en, this message translates to:
  /// **'Open image in browser'**
  String get openImage;

  /// No description provided for @problemIncompatible.
  ///
  /// In en, this message translates to:
  /// **'The server data is incompatible with this app'**
  String get problemIncompatible;

  /// No description provided for @problemAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Check the access token'**
  String get problemAuthentication;

  /// No description provided for @problemSessionOffline.
  ///
  /// In en, this message translates to:
  /// **'The TSPi session is offline'**
  String get problemSessionOffline;

  /// No description provided for @problemSessionChanged.
  ///
  /// In en, this message translates to:
  /// **'The session changed. Synchronize again'**
  String get problemSessionChanged;

  /// No description provided for @problemServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The TS Phone service is temporarily unavailable'**
  String get problemServiceUnavailable;

  /// No description provided for @problemConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the TS Phone service'**
  String get problemConnectionFailed;

  /// No description provided for @problemRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Synchronization timed out. Try again'**
  String get problemRequestTimeout;

  /// No description provided for @problemRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'The server request failed'**
  String get problemRequestFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
