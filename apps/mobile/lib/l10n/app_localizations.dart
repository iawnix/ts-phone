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

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

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

  /// No description provided for @connectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Connection details'**
  String get connectionDetails;

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

  /// No description provided for @clientVersionBuild.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · Build {build}'**
  String clientVersionBuild(String version, String build);

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'TS Phone server address'**
  String get endpoint;

  /// No description provided for @copyServerAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy server address'**
  String get copyServerAddress;

  /// No description provided for @serverAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Server address copied'**
  String get serverAddressCopied;

  /// No description provided for @copyServerAddressFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy server address'**
  String get copyServerAddressFailed;

  /// No description provided for @loadLaterMessages.
  ///
  /// In en, this message translates to:
  /// **'Load later messages'**
  String get loadLaterMessages;

  /// No description provided for @problemModelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No model is ready in this TSPi session. Check the model selection on the host.'**
  String get problemModelUnavailable;

  /// No description provided for @problemModelAuthMissing.
  ///
  /// In en, this message translates to:
  /// **'The model needs authentication on the TSPi host. Your TS Phone connection is still valid.'**
  String get problemModelAuthMissing;

  /// No description provided for @problemModelCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'The TSPi host could not verify the model configuration.'**
  String get problemModelCheckFailed;

  /// No description provided for @problemProviderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The model service is temporarily unavailable and this generation failed. You can send again later; tool actions already performed remain recorded.'**
  String get problemProviderUnavailable;

  /// No description provided for @problemProviderRateLimited.
  ///
  /// In en, this message translates to:
  /// **'The model service rejected this generation due to rate or quota limits. Try later or check the service quota.'**
  String get problemProviderRateLimited;

  /// No description provided for @problemProviderAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'The model service rejected authentication. Check the Host\'s upstream credentials; this is separate from your phone connection.'**
  String get problemProviderAuthFailed;

  /// No description provided for @problemProviderError.
  ///
  /// In en, this message translates to:
  /// **'The model service returned an error and this generation failed. Details remain in the Host\'s session history.'**
  String get problemProviderError;

  /// No description provided for @problemGenerationIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Execution ended without a confirmed complete reply. Review the conversation\'s output and tool results.'**
  String get problemGenerationIncomplete;

  /// No description provided for @problemModelStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'TSPi cannot access its model credentials or cache. Check the host service\'s Pi directory permissions.'**
  String get problemModelStorageUnavailable;

  /// No description provided for @problemRuntimeExtensionError.
  ///
  /// In en, this message translates to:
  /// **'An extension failed in this TSPi session. Check the latest messages and host logs.'**
  String get problemRuntimeExtensionError;

  /// No description provided for @problemPromptRejected.
  ///
  /// In en, this message translates to:
  /// **'Pi rejected this message before model execution. Your draft has been kept.'**
  String get problemPromptRejected;

  /// No description provided for @problemDeliveryUncertain.
  ///
  /// In en, this message translates to:
  /// **'Message delivery is unconfirmed. Check the latest history before sending again.'**
  String get problemDeliveryUncertain;

  /// No description provided for @messageDeliveryUncertain.
  ///
  /// In en, this message translates to:
  /// **'Delivery unconfirmed'**
  String get messageDeliveryUncertain;

  /// No description provided for @sessionConfiguredModel.
  ///
  /// In en, this message translates to:
  /// **'Startup model'**
  String get sessionConfiguredModel;

  /// No description provided for @sessionLastModel.
  ///
  /// In en, this message translates to:
  /// **'Last used model'**
  String get sessionLastModel;

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
  /// **'Check Phone service'**
  String get runDiagnostics;

  /// No description provided for @diagnosticsRunning.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get diagnosticsRunning;

  /// No description provided for @diagnosticConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get diagnosticConfigured;

  /// No description provided for @diagnosticVerified.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get diagnosticVerified;

  /// No description provided for @diagnosticFailed.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
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

  /// No description provided for @opening.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get opening;

  /// No description provided for @researchDirectoriesRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Research workspaces refreshed'**
  String get researchDirectoriesRefreshed;

  /// No description provided for @noWorkspacesTitle.
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get noWorkspacesTitle;

  /// No description provided for @noWorkspacesMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a project to start a separate TSPi research workspace.'**
  String get noWorkspacesMessage;

  /// No description provided for @workspaces.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get workspaces;

  /// No description provided for @activeItems.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get activeItems;

  /// No description provided for @archivedItems.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedItems;

  /// No description provided for @recentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted'**
  String get recentlyDeleted;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectName;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get createProject;

  /// No description provided for @newSession.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get newSession;

  /// No description provided for @sessionNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Session name (optional)'**
  String get sessionNameOptional;

  /// No description provided for @modelOptional.
  ///
  /// In en, this message translates to:
  /// **'Model (optional)'**
  String get modelOptional;

  /// No description provided for @createSession.
  ///
  /// In en, this message translates to:
  /// **'Create session'**
  String get createSession;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @moveToRecentlyDeleted.
  ///
  /// In en, this message translates to:
  /// **'Move to Recently Deleted'**
  String get moveToRecentlyDeleted;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @startSession.
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get startSession;

  /// No description provided for @startingSession.
  ///
  /// In en, this message translates to:
  /// **'Starting session'**
  String get startingSession;

  /// No description provided for @projectDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete project?'**
  String get projectDeleteTitle;

  /// No description provided for @projectDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This hides the project in Recently Deleted until you restore or permanently delete it.'**
  String get projectDeleteMessage;

  /// No description provided for @sessionDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete session?'**
  String get sessionDeleteTitle;

  /// No description provided for @sessionDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Only this conversation history is moved to Recently Deleted. Scientific project data is not removed.'**
  String get sessionDeleteMessage;

  /// No description provided for @permanentDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently?'**
  String get permanentDeleteTitle;

  /// No description provided for @permanentDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. Enter {resourceId} to continue.'**
  String permanentDeleteMessage(String resourceId);

  /// No description provided for @confirmationValue.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get confirmationValue;

  /// No description provided for @deletionBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Project cannot be deleted'**
  String get deletionBlockedTitle;

  /// No description provided for @deletionBlockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Resolve active workers, remote calculations, approvals, and remote effects first.'**
  String get deletionBlockedMessage;

  /// No description provided for @activeWorkers.
  ///
  /// In en, this message translates to:
  /// **'Active sessions'**
  String get activeWorkers;

  /// No description provided for @problemManagementChanged.
  ///
  /// In en, this message translates to:
  /// **'This project or session has changed. Refresh and try again.'**
  String get problemManagementChanged;

  /// No description provided for @problemResourcesBusy.
  ///
  /// In en, this message translates to:
  /// **'A session is still active or work remains unresolved. Finish it before continuing.'**
  String get problemResourcesBusy;

  /// No description provided for @problemPreflightUnavailable.
  ///
  /// In en, this message translates to:
  /// **'TSPi could not verify this operation. Check the Host\'s TSPi configuration and try again.'**
  String get problemPreflightUnavailable;

  /// No description provided for @problemManagementUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This Phone service does not support creating projects or sessions yet. Update the server installation; updating the app alone is not enough.'**
  String get problemManagementUnsupported;

  /// No description provided for @hostVersion.
  ///
  /// In en, this message translates to:
  /// **'Server version'**
  String get hostVersion;

  /// No description provided for @problemManagementCapacity.
  ///
  /// In en, this message translates to:
  /// **'Project and session storage is full. Remove unneeded items before adding more.'**
  String get problemManagementCapacity;

  /// No description provided for @remoteCalculations.
  ///
  /// In en, this message translates to:
  /// **'Remote calculations'**
  String get remoteCalculations;

  /// No description provided for @pendingApprovals.
  ///
  /// In en, this message translates to:
  /// **'Pending approvals'**
  String get pendingApprovals;

  /// No description provided for @unresolvedRemoteEffects.
  ///
  /// In en, this message translates to:
  /// **'Unresolved remote effects'**
  String get unresolvedRemoteEffects;

  /// No description provided for @archiveEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No archived items'**
  String get archiveEmptyTitle;

  /// No description provided for @trashEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently Deleted is empty'**
  String get trashEmptyTitle;

  /// No description provided for @archivedItemsMessage.
  ///
  /// In en, this message translates to:
  /// **'Archived items stay available here until restored or deleted.'**
  String get archivedItemsMessage;

  /// No description provided for @recentlyDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'Deleted items can be restored before permanent removal.'**
  String get recentlyDeletedMessage;

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
  /// **'No sessions yet'**
  String get noSessionHistoryTitle;

  /// No description provided for @noSessionHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a session to begin or continue work in this project.'**
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
  /// **'Research'**
  String get accessController;

  /// No description provided for @accessObserver.
  ///
  /// In en, this message translates to:
  /// **'Read-only Q&A'**
  String get accessObserver;

  /// No description provided for @historySession.
  ///
  /// In en, this message translates to:
  /// **'History session'**
  String get historySession;

  /// No description provided for @historyReadOnlyStatus.
  ///
  /// In en, this message translates to:
  /// **'History · Read-only'**
  String get historyReadOnlyStatus;

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

  /// No description provided for @sessionRuntimeTapHint.
  ///
  /// In en, this message translates to:
  /// **'View session details'**
  String get sessionRuntimeTapHint;

  /// No description provided for @sessionRuntimeDetails.
  ///
  /// In en, this message translates to:
  /// **'Session details'**
  String get sessionRuntimeDetails;

  /// No description provided for @sessionRuntimeLastKnown.
  ///
  /// In en, this message translates to:
  /// **'TSPi is offline. These are the last known runtime values.'**
  String get sessionRuntimeLastKnown;

  /// No description provided for @sessionRuntimeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No runtime snapshot was saved for this session.'**
  String get sessionRuntimeUnavailable;

  /// No description provided for @copySessionId.
  ///
  /// In en, this message translates to:
  /// **'Copy session ID'**
  String get copySessionId;

  /// No description provided for @sessionIdCopied.
  ///
  /// In en, this message translates to:
  /// **'Session ID copied'**
  String get sessionIdCopied;

  /// No description provided for @copySessionIdFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy session ID'**
  String get copySessionIdFailed;

  /// No description provided for @sessionModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get sessionModel;

  /// No description provided for @sessionProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get sessionProvider;

  /// No description provided for @sessionContextWindow.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get sessionContextWindow;

  /// No description provided for @sessionContextRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get sessionContextRemaining;

  /// No description provided for @sessionContextSource.
  ///
  /// In en, this message translates to:
  /// **'Measurement'**
  String get sessionContextSource;

  /// No description provided for @sessionContextEstimate.
  ///
  /// In en, this message translates to:
  /// **'Pi estimate'**
  String get sessionContextEstimate;

  /// No description provided for @sessionContextUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get sessionContextUnavailable;

  /// No description provided for @sessionRuntimeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get sessionRuntimeUpdated;

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

  /// No description provided for @abortTargetChanged.
  ///
  /// In en, this message translates to:
  /// **'The active generation changed. Nothing was stopped.'**
  String get abortTargetChanged;

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

  /// No description provided for @abortGenerationConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Stop the current generation? The partial response may be incomplete.'**
  String get abortGenerationConfirmation;

  /// No description provided for @keepGenerating.
  ///
  /// In en, this message translates to:
  /// **'Keep generating'**
  String get keepGenerating;

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
  /// **'Message'**
  String get composerMessage;

  /// No description provided for @composerReadOnly.
  ///
  /// In en, this message translates to:
  /// **'History is read-only'**
  String get composerReadOnly;

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

  /// No description provided for @loadAllHistory.
  ///
  /// In en, this message translates to:
  /// **'Load all history'**
  String get loadAllHistory;

  /// No description provided for @loadingAllHistory.
  ///
  /// In en, this message translates to:
  /// **'Loading all history'**
  String get loadingAllHistory;

  /// No description provided for @timelineProgress.
  ///
  /// In en, this message translates to:
  /// **'{loaded} / {total} items'**
  String timelineProgress(int loaded, int total);

  /// No description provided for @timelineTurns.
  ///
  /// In en, this message translates to:
  /// **'{count} turns'**
  String timelineTurns(int count);

  /// No description provided for @timelineActivities.
  ///
  /// In en, this message translates to:
  /// **'{count} activities'**
  String timelineActivities(int count);

  /// No description provided for @timelineFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get timelineFilterAll;

  /// No description provided for @timelineFilterMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get timelineFilterMessages;

  /// No description provided for @timelineFilterActivities.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get timelineFilterActivities;

  /// No description provided for @timelineFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items in this view'**
  String get timelineFilterEmpty;

  /// No description provided for @timelineBranches.
  ///
  /// In en, this message translates to:
  /// **'Session branches'**
  String get timelineBranches;

  /// No description provided for @timelineActiveBranch.
  ///
  /// In en, this message translates to:
  /// **'Active branch'**
  String get timelineActiveBranch;

  /// No description provided for @timelineBranchLabel.
  ///
  /// In en, this message translates to:
  /// **'Branch {shortId}'**
  String timelineBranchLabel(String shortId);

  /// No description provided for @timelineTurnLabel.
  ///
  /// In en, this message translates to:
  /// **'Turn {number}'**
  String timelineTurnLabel(int number);

  /// No description provided for @timelineSubagent.
  ///
  /// In en, this message translates to:
  /// **'Subagent'**
  String get timelineSubagent;

  /// No description provided for @timelineResearch.
  ///
  /// In en, this message translates to:
  /// **'Research'**
  String get timelineResearch;

  /// No description provided for @timelineReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get timelineReview;

  /// No description provided for @timelineWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get timelineWorkspace;

  /// No description provided for @timelineConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get timelineConfiguration;

  /// No description provided for @timelineModelChange.
  ///
  /// In en, this message translates to:
  /// **'Model changed'**
  String get timelineModelChange;

  /// No description provided for @timelineThinkingLevelChange.
  ///
  /// In en, this message translates to:
  /// **'Thinking level changed'**
  String get timelineThinkingLevelChange;

  /// No description provided for @timelineSessionInfo.
  ///
  /// In en, this message translates to:
  /// **'Session information'**
  String get timelineSessionInfo;

  /// No description provided for @timelineContext.
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get timelineContext;

  /// No description provided for @timelineSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get timelineSystem;

  /// No description provided for @timelineCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get timelineCompleted;

  /// No description provided for @timelineFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get timelineFailed;

  /// No description provided for @timelineRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get timelineRecorded;

  /// No description provided for @timelineStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get timelineStage;

  /// No description provided for @timelineNodes.
  ///
  /// In en, this message translates to:
  /// **'Research nodes'**
  String get timelineNodes;

  /// No description provided for @timelineReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get timelineReference;

  /// No description provided for @timelineRetrySafe.
  ///
  /// In en, this message translates to:
  /// **'Safe to retry'**
  String get timelineRetrySafe;

  /// No description provided for @timelineRetryUnsafe.
  ///
  /// In en, this message translates to:
  /// **'Do not retry automatically'**
  String get timelineRetryUnsafe;

  /// No description provided for @timelineDuration.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String timelineDuration(String seconds);

  /// No description provided for @timelineTokens.
  ///
  /// In en, this message translates to:
  /// **'{count} tokens'**
  String timelineTokens(int count);

  /// No description provided for @composerHistoricalBranch.
  ///
  /// In en, this message translates to:
  /// **'Read-only historical branch'**
  String get composerHistoricalBranch;

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

  /// No description provided for @previewImage.
  ///
  /// In en, this message translates to:
  /// **'Preview image'**
  String get previewImage;

  /// No description provided for @loadingImage.
  ///
  /// In en, this message translates to:
  /// **'Loading image'**
  String get loadingImage;

  /// No description provided for @imageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'The image could not be loaded'**
  String get imageLoadFailed;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openInBrowser;

  /// No description provided for @settingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load settings from this device. Try again.'**
  String get settingsLoadFailed;

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

  /// No description provided for @problemAgentRunChanged.
  ///
  /// In en, this message translates to:
  /// **'The active generation changed before it could be stopped'**
  String get problemAgentRunChanged;

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

  /// No description provided for @problemApiRouteMissing.
  ///
  /// In en, this message translates to:
  /// **'The requested API endpoint does not exist. Check that the app and Host are up to date.'**
  String get problemApiRouteMissing;

  /// No description provided for @problemQueueStorage.
  ///
  /// In en, this message translates to:
  /// **'Host could not confirm request storage. Check its state directory before retrying.'**
  String get problemQueueStorage;

  /// No description provided for @problemQueueCapacity.
  ///
  /// In en, this message translates to:
  /// **'The request queue or its receipt storage is full. Finish pending requests or check Host storage.'**
  String get problemQueueCapacity;

  /// No description provided for @problemQueueRecovery.
  ///
  /// In en, this message translates to:
  /// **'A previous request has an uncertain outcome. Review its history and outputs before continuing the queue.'**
  String get problemQueueRecovery;

  /// No description provided for @commandQueue.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get commandQueue;

  /// No description provided for @commandQueueCount.
  ///
  /// In en, this message translates to:
  /// **'Up next · {count}'**
  String commandQueueCount(int count);

  /// No description provided for @commandQueuePending.
  ///
  /// In en, this message translates to:
  /// **'Messages waiting'**
  String get commandQueuePending;

  /// No description provided for @commandQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No messages waiting'**
  String get commandQueueEmpty;

  /// No description provided for @commandQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting · {position}'**
  String commandQueued(int position);

  /// No description provided for @commandStarting.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get commandStarting;

  /// No description provided for @commandRunning.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get commandRunning;

  /// No description provided for @commandCompleted.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get commandCompleted;

  /// No description provided for @commandFailed.
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get commandFailed;

  /// No description provided for @commandUnknown.
  ///
  /// In en, this message translates to:
  /// **'Needs verification'**
  String get commandUnknown;

  /// No description provided for @commandCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get commandCancelled;

  /// No description provided for @commandAcknowledged.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get commandAcknowledged;

  /// No description provided for @cancelQueuedRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel waiting request'**
  String get cancelQueuedRequest;

  /// No description provided for @acknowledgeRequest.
  ///
  /// In en, this message translates to:
  /// **'Confirm review'**
  String get acknowledgeRequest;

  /// No description provided for @acknowledgeRequestBody.
  ///
  /// In en, this message translates to:
  /// **'Confirm that you have checked this request\'s conversation and outputs. This releases later requests without repeating this one or claiming that it succeeded. Its uncertain runtime must already be stopped.'**
  String get acknowledgeRequestBody;

  /// No description provided for @commandWaitingForCurrent.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the current reply'**
  String get commandWaitingForCurrent;

  /// No description provided for @commandOtherConversationWaiting.
  ///
  /// In en, this message translates to:
  /// **'Another conversation is waiting'**
  String get commandOtherConversationWaiting;

  /// No description provided for @commandOtherConversation.
  ///
  /// In en, this message translates to:
  /// **'Another conversation'**
  String get commandOtherConversation;

  /// No description provided for @commandNeedsReview.
  ///
  /// In en, this message translates to:
  /// **'A previous request needs review'**
  String get commandNeedsReview;

  /// No description provided for @modelNextTurn.
  ///
  /// In en, this message translates to:
  /// **'Model for new and waiting messages'**
  String get modelNextTurn;

  /// No description provided for @filterConversations.
  ///
  /// In en, this message translates to:
  /// **'Filter conversations'**
  String get filterConversations;

  /// No description provided for @searchConversations.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get searchConversations;

  /// No description provided for @openSidebar.
  ///
  /// In en, this message translates to:
  /// **'Projects and conversations'**
  String get openSidebar;

  /// No description provided for @switchProject.
  ///
  /// In en, this message translates to:
  /// **'Switch project'**
  String get switchProject;

  /// No description provided for @continueSession.
  ///
  /// In en, this message translates to:
  /// **'Continue conversation'**
  String get continueSession;

  /// No description provided for @readOnlyAssistant.
  ///
  /// In en, this message translates to:
  /// **'Read-only Q&A'**
  String get readOnlyAssistant;

  /// No description provided for @sessionMode.
  ///
  /// In en, this message translates to:
  /// **'Conversation mode'**
  String get sessionMode;

  /// No description provided for @workspaceReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Workspace access: read-only'**
  String get workspaceReadOnly;

  /// No description provided for @workspaceReadWrite.
  ///
  /// In en, this message translates to:
  /// **'Workspace access: read and write'**
  String get workspaceReadWrite;

  /// No description provided for @switchAssistantMode.
  ///
  /// In en, this message translates to:
  /// **'Switch to {mode}?'**
  String switchAssistantMode(String mode);

  /// No description provided for @switchAssistantModeBody.
  ///
  /// In en, this message translates to:
  /// **'The idle assistant will restart in this conversation. History and submitted calculations stay intact. If startup fails, you can start the conversation again.'**
  String get switchAssistantModeBody;

  /// No description provided for @activationUpgradeRequired.
  ///
  /// In en, this message translates to:
  /// **'Update the TSPi Host to choose a session mode. History remains available.'**
  String get activationUpgradeRequired;

  /// No description provided for @activationWriterActive.
  ///
  /// In en, this message translates to:
  /// **'Another process owns this workspace or conversation. Close it on the Host before continuing. History and drafts are kept.'**
  String get activationWriterActive;

  /// No description provided for @activationInspectionFailed.
  ///
  /// In en, this message translates to:
  /// **'The Host could not complete the session guard check. Check the TSPi installation diagnostics before retrying. History and drafts are kept.'**
  String get activationInspectionFailed;

  /// No description provided for @activationGuardInvalid.
  ///
  /// In en, this message translates to:
  /// **'The Host could not validate the session history or its writer locks. Inspect the session files on the Host. Do not delete history or lock files to bypass this check.'**
  String get activationGuardInvalid;

  /// No description provided for @activationExternalOwner.
  ///
  /// In en, this message translates to:
  /// **'This workspace is open in a terminal. Continue that conversation or close it before switching.'**
  String get activationExternalOwner;

  /// No description provided for @activationSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue research in this conversation?'**
  String get activationSwitchTitle;

  /// No description provided for @activationSwitchBody.
  ///
  /// In en, this message translates to:
  /// **'The idle runtime for {name} will stop. Its history and remote calculations are kept. A failed start will not restart it automatically.'**
  String activationSwitchBody(String name);

  /// No description provided for @activationSwitchConfirm.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get activationSwitchConfirm;

  /// No description provided for @activationOpenOwner.
  ///
  /// In en, this message translates to:
  /// **'Open conversation'**
  String get activationOpenOwner;

  /// No description provided for @activationFailed.
  ///
  /// In en, this message translates to:
  /// **'The conversation did not become ready. Refresh and check the Host configuration. A runtime stopped during switching will stay offline; history and drafts are kept.'**
  String get activationFailed;

  /// No description provided for @activationOutcomeUnknown.
  ///
  /// In en, this message translates to:
  /// **'The activation result was not received. The Host may still be preparing this conversation. Refresh its state before trying again.'**
  String get activationOutcomeUnknown;

  /// No description provided for @activationCapacity.
  ///
  /// In en, this message translates to:
  /// **'The Host\'s activation records are full. Wait for active runs to settle, arrange a Host restart, then refresh.'**
  String get activationCapacity;

  /// No description provided for @activationRecoveryRequired.
  ///
  /// In en, this message translates to:
  /// **'The conversation process could not be confirmed. Inspect it on the Host before continuing. No message will be resent automatically.'**
  String get activationRecoveryRequired;

  /// No description provided for @preparingSession.
  ///
  /// In en, this message translates to:
  /// **'Preparing conversation'**
  String get preparingSession;

  /// No description provided for @localDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get localDraft;

  /// No description provided for @chatWelcome.
  ///
  /// In en, this message translates to:
  /// **'What are we investigating?'**
  String get chatWelcome;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @recentConversations.
  ///
  /// In en, this message translates to:
  /// **'Recent conversations'**
  String get recentConversations;

  /// No description provided for @noRecentConversations.
  ///
  /// In en, this message translates to:
  /// **'No recent conversations'**
  String get noRecentConversations;

  /// No description provided for @recentConversationsIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some conversations could not be refreshed'**
  String get recentConversationsIncomplete;

  /// No description provided for @unnamedConversation.
  ///
  /// In en, this message translates to:
  /// **'Untitled conversation'**
  String get unnamedConversation;

  /// No description provided for @dataNotProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get dataNotProvided;

  /// No description provided for @accessPermission.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get accessPermission;

  /// No description provided for @technicalDetails.
  ///
  /// In en, this message translates to:
  /// **'Technical details'**
  String get technicalDetails;

  /// No description provided for @messageNoText.
  ///
  /// In en, this message translates to:
  /// **'No displayable response in this record'**
  String get messageNoText;

  /// No description provided for @messageNotDisplayed.
  ///
  /// In en, this message translates to:
  /// **'This record has no displayable text'**
  String get messageNotDisplayed;

  /// No description provided for @messageGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get messageGenerationFailed;

  /// No description provided for @messageGenerationAborted.
  ///
  /// In en, this message translates to:
  /// **'Generation stopped'**
  String get messageGenerationAborted;

  /// No description provided for @activityRecords.
  ///
  /// In en, this message translates to:
  /// **'{count} activity records'**
  String activityRecords(int count);

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutApp;

  /// No description provided for @chooseModel.
  ///
  /// In en, this message translates to:
  /// **'Choose model'**
  String get chooseModel;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @searchModels.
  ///
  /// In en, this message translates to:
  /// **'Search models'**
  String get searchModels;

  /// No description provided for @noModelsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No available models'**
  String get noModelsAvailable;

  /// No description provided for @hostDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Host default model'**
  String get hostDefaultModel;

  /// No description provided for @modelSelectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Wait for synchronization and pending messages to finish before switching models.'**
  String get modelSelectionUnavailable;

  /// No description provided for @modelSelectionBusy.
  ///
  /// In en, this message translates to:
  /// **'The assistant is busy. Switch models after this response finishes.'**
  String get modelSelectionBusy;

  /// No description provided for @modelSelectionHostRequired.
  ///
  /// In en, this message translates to:
  /// **'Only Host-managed conversations can switch models here.'**
  String get modelSelectionHostRequired;

  /// No description provided for @modelSelectionStartRequired.
  ///
  /// In en, this message translates to:
  /// **'Continue this conversation before changing its model.'**
  String get modelSelectionStartRequired;

  /// No description provided for @modelPreference.
  ///
  /// In en, this message translates to:
  /// **'Model for the next conversation start'**
  String get modelPreference;

  /// No description provided for @viewFullOutput.
  ///
  /// In en, this message translates to:
  /// **'View full output'**
  String get viewFullOutput;

  /// No description provided for @copyOutput.
  ///
  /// In en, this message translates to:
  /// **'Copy full output'**
  String get copyOutput;

  /// No description provided for @outputCopied.
  ///
  /// In en, this message translates to:
  /// **'Output copied'**
  String get outputCopied;

  /// No description provided for @outputCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy output'**
  String get outputCopyFailed;

  /// No description provided for @contentDisplayFailed.
  ///
  /// In en, this message translates to:
  /// **'This content could not be displayed.'**
  String get contentDisplayFailed;

  /// No description provided for @activityFailureCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 failed activity} other{{count} failed activities}}'**
  String activityFailureCount(int count);

  /// No description provided for @viewAllActivities.
  ///
  /// In en, this message translates to:
  /// **'View all {count} activities'**
  String viewAllActivities(int count);

  /// No description provided for @projectViews.
  ///
  /// In en, this message translates to:
  /// **'Project lists'**
  String get projectViews;

  /// No description provided for @sessionViews.
  ///
  /// In en, this message translates to:
  /// **'Conversation lists'**
  String get sessionViews;

  /// No description provided for @archivedProjects.
  ///
  /// In en, this message translates to:
  /// **'Archived projects'**
  String get archivedProjects;

  /// No description provided for @deletedProjects.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted projects'**
  String get deletedProjects;

  /// No description provided for @archivedSessions.
  ///
  /// In en, this message translates to:
  /// **'Archived conversations'**
  String get archivedSessions;

  /// No description provided for @deletedSessions.
  ///
  /// In en, this message translates to:
  /// **'Recently deleted conversations'**
  String get deletedSessions;

  /// No description provided for @chatReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get chatReady;

  /// No description provided for @chatRunning.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get chatRunning;

  /// No description provided for @chatConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get chatConnecting;

  /// No description provided for @chatReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get chatReconnecting;

  /// No description provided for @chatOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get chatOffline;

  /// No description provided for @chatRecovery.
  ///
  /// In en, this message translates to:
  /// **'Needs recovery'**
  String get chatRecovery;

  /// No description provided for @chatFailed.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get chatFailed;

  /// No description provided for @chatHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get chatHistory;

  /// No description provided for @chatCanContinue.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get chatCanContinue;

  /// No description provided for @activityRead.
  ///
  /// In en, this message translates to:
  /// **'Read file'**
  String get activityRead;

  /// No description provided for @activityWrite.
  ///
  /// In en, this message translates to:
  /// **'Write file'**
  String get activityWrite;

  /// No description provided for @activityShell.
  ///
  /// In en, this message translates to:
  /// **'Run command'**
  String get activityShell;

  /// No description provided for @activityState.
  ///
  /// In en, this message translates to:
  /// **'Read workspace'**
  String get activityState;

  /// No description provided for @activityChange.
  ///
  /// In en, this message translates to:
  /// **'Record research decision'**
  String get activityChange;

  /// No description provided for @activityReview.
  ///
  /// In en, this message translates to:
  /// **'Independent review'**
  String get activityReview;

  /// No description provided for @activityReply.
  ///
  /// In en, this message translates to:
  /// **'Respond to review'**
  String get activityReply;

  /// No description provided for @activityCalculation.
  ///
  /// In en, this message translates to:
  /// **'Calculation'**
  String get activityCalculation;

  /// No description provided for @activityRemote.
  ///
  /// In en, this message translates to:
  /// **'Remote task'**
  String get activityRemote;
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
