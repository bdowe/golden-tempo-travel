import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

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
    Locale('es')
  ];

  /// Product name. Not translated — it is a brand name.
  ///
  /// In en, this message translates to:
  /// **'Golden Tempo Travel'**
  String get appTitle;

  /// Header of the language group in account settings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSectionTitle;

  /// Language option that follows the device/browser language.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystemDefault;

  /// Name of the English language, shown in its own language.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Name of the Spanish language, shown in its own language.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get languageSpanish;

  /// Explains that switching language does not retranslate existing saved content.
  ///
  /// In en, this message translates to:
  /// **'Trips and notes you already saved stay in the language they were written in.'**
  String get languageChangeNote;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get commonSeeAll;

  /// Destination summary for a trip with exactly two hub cities.
  ///
  /// In en, this message translates to:
  /// **'{first} & {second}'**
  String citiesTwo(String first, String second);

  /// Destination summary for a trip with more than two hub cities; count is how many are not named.
  ///
  /// In en, this message translates to:
  /// **'{first} & {second} +{count} more'**
  String citiesMore(String first, String second, int count);

  /// No description provided for @prefsTitle.
  ///
  /// In en, this message translates to:
  /// **'Travel profile'**
  String get prefsTitle;

  /// No description provided for @prefsBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get prefsBudget;

  /// No description provided for @prefsPace.
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get prefsPace;

  /// No description provided for @prefsInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get prefsInterests;

  /// No description provided for @prefsAddInterest.
  ///
  /// In en, this message translates to:
  /// **'Add an interest'**
  String get prefsAddInterest;

  /// No description provided for @prefsHomeAirport.
  ///
  /// In en, this message translates to:
  /// **'Home airport'**
  String get prefsHomeAirport;

  /// No description provided for @prefsHomeAirportHelp.
  ///
  /// In en, this message translates to:
  /// **'Used as the default origin when planning flights.'**
  String get prefsHomeAirportHelp;

  /// No description provided for @prefsProfileNotes.
  ///
  /// In en, this message translates to:
  /// **'Profile notes'**
  String get prefsProfileNotes;

  /// No description provided for @prefsProfileNotesHelp.
  ///
  /// In en, this message translates to:
  /// **'Your AI agent keeps these notes as it learns about you. Edit or clear them anytime.'**
  String get prefsProfileNotesHelp;

  /// No description provided for @prefsProfileNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing noted yet — the agent adds to this as you plan trips.'**
  String get prefsProfileNotesHint;

  /// No description provided for @prefsSaved.
  ///
  /// In en, this message translates to:
  /// **'Preferences saved'**
  String get prefsSaved;

  /// No description provided for @prefsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save preferences'**
  String get prefsSaveFailed;

  /// Budget level option shown on a chip; the stored API value stays 'budget'.
  ///
  /// In en, this message translates to:
  /// **'budget'**
  String get prefsBudgetLow;

  /// No description provided for @prefsBudgetMid.
  ///
  /// In en, this message translates to:
  /// **'mid'**
  String get prefsBudgetMid;

  /// No description provided for @prefsBudgetLuxury.
  ///
  /// In en, this message translates to:
  /// **'luxury'**
  String get prefsBudgetLuxury;

  /// Trip pace option shown on a chip; the stored API value stays 'relaxed'.
  ///
  /// In en, this message translates to:
  /// **'relaxed'**
  String get prefsPaceRelaxed;

  /// No description provided for @prefsPaceBalanced.
  ///
  /// In en, this message translates to:
  /// **'balanced'**
  String get prefsPaceBalanced;

  /// No description provided for @prefsPacePacked.
  ///
  /// In en, this message translates to:
  /// **'packed'**
  String get prefsPacePacked;

  /// Suggested interest chip; the stored API value stays 'museums'.
  ///
  /// In en, this message translates to:
  /// **'museums'**
  String get prefsInterestMuseums;

  /// No description provided for @prefsInterestFood.
  ///
  /// In en, this message translates to:
  /// **'food'**
  String get prefsInterestFood;

  /// No description provided for @prefsInterestNightlife.
  ///
  /// In en, this message translates to:
  /// **'nightlife'**
  String get prefsInterestNightlife;

  /// No description provided for @prefsInterestNature.
  ///
  /// In en, this message translates to:
  /// **'nature'**
  String get prefsInterestNature;

  /// No description provided for @prefsInterestHistory.
  ///
  /// In en, this message translates to:
  /// **'history'**
  String get prefsInterestHistory;

  /// No description provided for @prefsInterestArt.
  ///
  /// In en, this message translates to:
  /// **'art'**
  String get prefsInterestArt;

  /// No description provided for @prefsInterestShopping.
  ///
  /// In en, this message translates to:
  /// **'shopping'**
  String get prefsInterestShopping;

  /// No description provided for @prefsInterestOutdoors.
  ///
  /// In en, this message translates to:
  /// **'outdoors'**
  String get prefsInterestOutdoors;

  /// No description provided for @prefsInterestBeaches.
  ///
  /// In en, this message translates to:
  /// **'beaches'**
  String get prefsInterestBeaches;

  /// No description provided for @prefsInterestArchitecture.
  ///
  /// In en, this message translates to:
  /// **'architecture'**
  String get prefsInterestArchitecture;

  /// No description provided for @ssoContinueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get ssoContinueWithGoogle;

  /// No description provided for @ssoContinueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get ssoContinueWithApple;

  /// No description provided for @ssoDividerOr.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get ssoDividerOr;

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// No description provided for @authCreateAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateAccountTitle;

  /// No description provided for @authEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// No description provided for @authEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get authEmailRequired;

  /// No description provided for @authEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get authEmailInvalid;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get authPasswordRequired;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get authPasswordTooShort;

  /// No description provided for @authDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get authDisplayNameLabel;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authNoAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get authNoAccountPrompt;

  /// No description provided for @authHaveAccountPrompt.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get authHaveAccountPrompt;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authPasswordUpdatedSnack.
  ///
  /// In en, this message translates to:
  /// **'Password updated — sign in with your new password'**
  String get authPasswordUpdatedSnack;

  /// No description provided for @authResetDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get authResetDialogTitle;

  /// No description provided for @authResetDialogBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll email you a reset code if this address has an account.'**
  String get authResetDialogBody;

  /// No description provided for @authSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get authSending;

  /// No description provided for @authSendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get authSendCode;

  /// No description provided for @authEnterCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your reset code'**
  String get authEnterCodeTitle;

  /// No description provided for @authEnterCodeBody.
  ///
  /// In en, this message translates to:
  /// **'Check your inbox for the code we just sent.'**
  String get authEnterCodeBody;

  /// No description provided for @authResetCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Reset code'**
  String get authResetCodeLabel;

  /// No description provided for @authNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPasswordLabel;

  /// No description provided for @authCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Paste the code from the email'**
  String get authCodeRequired;

  /// No description provided for @authSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get authSaving;

  /// No description provided for @authSetNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get authSetNewPassword;

  /// No description provided for @resetAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetAppBarTitle;

  /// No description provided for @resetSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get resetSuccessTitle;

  /// No description provided for @resetSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your new password. Any other sessions were signed out.'**
  String get resetSuccessBody;

  /// No description provided for @resetSignInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get resetSignInButton;

  /// No description provided for @resetChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password'**
  String get resetChooseTitle;

  /// No description provided for @resetNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get resetNewPasswordLabel;

  /// No description provided for @resetPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get resetPasswordRequired;

  /// No description provided for @resetPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get resetPasswordTooShort;

  /// No description provided for @resetConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get resetConfirmLabel;

  /// No description provided for @resetConfirmRequired.
  ///
  /// In en, this message translates to:
  /// **'Confirm your new password'**
  String get resetConfirmRequired;

  /// No description provided for @resetPasswordsMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get resetPasswordsMismatch;

  /// No description provided for @resetSetNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Set new password'**
  String get resetSetNewPassword;

  /// No description provided for @landingSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get landingSignIn;

  /// No description provided for @landingHeroTagline.
  ///
  /// In en, this message translates to:
  /// **'Plan less. Travel more.'**
  String get landingHeroTagline;

  /// No description provided for @landingHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your AI travel companion — describe the trip you want and get a full day-by-day itinerary with routes, places, and flights.'**
  String get landingHeroSubtitle;

  /// No description provided for @landingHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get landingHaveAccount;

  /// No description provided for @landingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get landingGetStarted;

  /// No description provided for @landingFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Everything you need to plan the trip'**
  String get landingFeaturesTitle;

  /// No description provided for @landingFeatureAgentTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Travel Agent'**
  String get landingFeatureAgentTitle;

  /// No description provided for @landingFeatureAgentDescription.
  ///
  /// In en, this message translates to:
  /// **'Describe your dream trip and get a complete itinerary in seconds.'**
  String get landingFeatureAgentDescription;

  /// No description provided for @landingPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get landingPrivacyPolicy;

  /// No description provided for @landingTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get landingTermsOfService;

  /// No description provided for @landingCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Golden Tempo LLC'**
  String get landingCopyright;

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get verifyTitle;

  /// No description provided for @verifySuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Email verified ✓'**
  String get verifySuccessTitle;

  /// No description provided for @verifySuccessBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set — thanks for confirming your address.'**
  String get verifySuccessBody;

  /// No description provided for @verifyLinkExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Link expired or already used'**
  String get verifyLinkExpiredTitle;

  /// No description provided for @verifyLinkExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'Request a new verification email from your account.'**
  String get verifyLinkExpiredBody;

  /// No description provided for @verifyContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get verifyContinue;

  /// No description provided for @ssoTitle.
  ///
  /// In en, this message translates to:
  /// **'Signing you in'**
  String get ssoTitle;

  /// No description provided for @ssoFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign-in didn\'t complete'**
  String get ssoFailedTitle;

  /// No description provided for @ssoErrorCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled or failed. Please try again.'**
  String get ssoErrorCancelled;

  /// No description provided for @ssoErrorExpired.
  ///
  /// In en, this message translates to:
  /// **'This sign-in link expired. Please try again.'**
  String get ssoErrorExpired;

  /// No description provided for @ssoBackToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get ssoBackToSignIn;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get settingsTitle;

  /// No description provided for @settingsProfileSection.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get settingsProfileSection;

  /// No description provided for @settingsDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get settingsDisplayName;

  /// No description provided for @settingsSaveName.
  ///
  /// In en, this message translates to:
  /// **'Save name'**
  String get settingsSaveName;

  /// No description provided for @settingsNameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Name updated'**
  String get settingsNameUpdated;

  /// No description provided for @settingsPasswordSection.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsPasswordSection;

  /// No description provided for @settingsCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get settingsCurrentPassword;

  /// No description provided for @settingsNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password (8+ characters)'**
  String get settingsNewPassword;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// No description provided for @settingsPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed — other devices were signed out'**
  String get settingsPasswordChanged;

  /// No description provided for @settingsSessionsSection.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get settingsSessionsSection;

  /// No description provided for @settingsSessionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Signs you out on every device, including this one.'**
  String get settingsSessionsHelp;

  /// No description provided for @settingsSignOutEverywhere.
  ///
  /// In en, this message translates to:
  /// **'Sign out everywhere'**
  String get settingsSignOutEverywhere;

  /// No description provided for @settingsEmailPrefsSection.
  ///
  /// In en, this message translates to:
  /// **'Email preferences'**
  String get settingsEmailPrefsSection;

  /// No description provided for @settingsTripReminders.
  ///
  /// In en, this message translates to:
  /// **'Trip reminders'**
  String get settingsTripReminders;

  /// No description provided for @settingsTripRemindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nudges about upcoming trips and things left to book.'**
  String get settingsTripRemindersSubtitle;

  /// No description provided for @settingsWeeklyIdeas.
  ///
  /// In en, this message translates to:
  /// **'Weekly planning ideas'**
  String get settingsWeeklyIdeas;

  /// No description provided for @settingsWeeklyIdeasSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A weekly email with destination ideas and inspiration.'**
  String get settingsWeeklyIdeasSubtitle;

  /// No description provided for @settingsLegalSection.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsLegalSection;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTermsOfService;

  /// No description provided for @settingsDangerZoneSection.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get settingsDangerZoneSection;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get settingsDeleteAccountTitle;

  /// No description provided for @settingsDeleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account, trips, preferences and alerts. There is no undo.'**
  String get settingsDeleteAccountBody;

  /// No description provided for @settingsConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm your password'**
  String get settingsConfirmPassword;

  /// No description provided for @settingsDeleteForever.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get settingsDeleteForever;

  /// No description provided for @quizTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your travel profile'**
  String get quizTitle;

  /// No description provided for @quizSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get quizSkip;

  /// No description provided for @quizFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get quizFinish;

  /// No description provided for @quizStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'What\'s your travel style?'**
  String get quizStyleTitle;

  /// No description provided for @quizStyleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Helps the planner match stays and activities to you.'**
  String get quizStyleSubtitle;

  /// No description provided for @quizInterestsTitle.
  ///
  /// In en, this message translates to:
  /// **'What do you love doing on a trip?'**
  String get quizInterestsTitle;

  /// No description provided for @quizInterestsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick as many as you like.'**
  String get quizInterestsSubtitle;

  /// No description provided for @quizCompanionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Who do you usually travel with?'**
  String get quizCompanionsTitle;

  /// No description provided for @quizCompanionSolo.
  ///
  /// In en, this message translates to:
  /// **'solo'**
  String get quizCompanionSolo;

  /// No description provided for @quizCompanionPartner.
  ///
  /// In en, this message translates to:
  /// **'partner'**
  String get quizCompanionPartner;

  /// No description provided for @quizCompanionFriends.
  ///
  /// In en, this message translates to:
  /// **'friends'**
  String get quizCompanionFriends;

  /// No description provided for @quizCompanionFamily.
  ///
  /// In en, this message translates to:
  /// **'family with kids'**
  String get quizCompanionFamily;

  /// No description provided for @quizCompanionVaries.
  ///
  /// In en, this message translates to:
  /// **'it varies'**
  String get quizCompanionVaries;

  /// No description provided for @quizHomeAirportTitle.
  ///
  /// In en, this message translates to:
  /// **'Where do you fly from?'**
  String get quizHomeAirportTitle;

  /// No description provided for @quizTripsTitle.
  ///
  /// In en, this message translates to:
  /// **'Any trips you\'re dreaming about?'**
  String get quizTripsTitle;

  /// No description provided for @quizTripsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Places, seasons, occasions — the planner will keep them in mind.'**
  String get quizTripsSubtitle;

  /// No description provided for @quizTripsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Japan for cherry blossom season, a Greek island hop next summer…'**
  String get quizTripsHint;

  /// No description provided for @quizSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save your answers — try again, or skip for now.'**
  String get quizSaveFailed;

  /// No description provided for @quizProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Travel profile updated'**
  String get quizProfileUpdated;

  /// No description provided for @bookingCardEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get bookingCardEdit;

  /// No description provided for @bookingCardRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get bookingCardRemove;

  /// No description provided for @bookingCardBooked.
  ///
  /// In en, this message translates to:
  /// **'Booked'**
  String get bookingCardBooked;

  /// No description provided for @bookingCardOpenIn.
  ///
  /// In en, this message translates to:
  /// **'Open in {provider}'**
  String bookingCardOpenIn(String provider);

  /// No description provided for @bookingCardOpenSearch.
  ///
  /// In en, this message translates to:
  /// **'Open search'**
  String get bookingCardOpenSearch;

  /// No description provided for @calendarAddTo.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar'**
  String get calendarAddTo;

  /// No description provided for @calendarGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar'**
  String get calendarGoogle;

  /// No description provided for @calendarApple.
  ///
  /// In en, this message translates to:
  /// **'Apple Calendar (.ics)'**
  String get calendarApple;

  /// No description provided for @calendarExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the event: {error}'**
  String calendarExportFailed(String error);

  /// No description provided for @bookingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get bookingsTitle;

  /// No description provided for @bookingsAddStay.
  ///
  /// In en, this message translates to:
  /// **'Add stay'**
  String get bookingsAddStay;

  /// No description provided for @bookingsAddTransport.
  ///
  /// In en, this message translates to:
  /// **'Add transport'**
  String get bookingsAddTransport;

  /// No description provided for @bookingsAddBooking.
  ///
  /// In en, this message translates to:
  /// **'Add booking'**
  String get bookingsAddBooking;

  /// No description provided for @bookingsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet — add the stays, transport, and other bookings for your trip so it all lives in one place.'**
  String get bookingsEmptyMessage;

  /// No description provided for @bookingsStays.
  ///
  /// In en, this message translates to:
  /// **'Stays'**
  String get bookingsStays;

  /// No description provided for @bookingsTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get bookingsTransport;

  /// No description provided for @bookingsOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get bookingsOther;

  /// No description provided for @bookingsSuggested.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get bookingsSuggested;

  /// No description provided for @bookingsKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get bookingsKeep;

  /// No description provided for @bookingsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get bookingsEdit;

  /// No description provided for @bookingsDismissSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Dismiss suggestion'**
  String get bookingsDismissSuggestion;

  /// No description provided for @bookingsOpenListing.
  ///
  /// In en, this message translates to:
  /// **'Open listing'**
  String get bookingsOpenListing;

  /// No description provided for @bookingsEditStay.
  ///
  /// In en, this message translates to:
  /// **'Edit stay'**
  String get bookingsEditStay;

  /// No description provided for @bookingsRemoveStay.
  ///
  /// In en, this message translates to:
  /// **'Remove stay'**
  String get bookingsRemoveStay;

  /// No description provided for @bookingsOpenBooking.
  ///
  /// In en, this message translates to:
  /// **'Open booking'**
  String get bookingsOpenBooking;

  /// No description provided for @bookingsEditTransport.
  ///
  /// In en, this message translates to:
  /// **'Edit transport'**
  String get bookingsEditTransport;

  /// No description provided for @bookingsRemoveTransport.
  ///
  /// In en, this message translates to:
  /// **'Remove transport'**
  String get bookingsRemoveTransport;

  /// No description provided for @bookingsAddAStay.
  ///
  /// In en, this message translates to:
  /// **'Add a stay'**
  String get bookingsAddAStay;

  /// No description provided for @bookingsStayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get bookingsStayNameLabel;

  /// No description provided for @bookingsStayProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider (Airbnb, Booking.com, …)'**
  String get bookingsStayProviderLabel;

  /// No description provided for @bookingsStayUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Listing URL'**
  String get bookingsStayUrlLabel;

  /// No description provided for @bookingsStayAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get bookingsStayAddressLabel;

  /// No description provided for @bookingsCheckInOut.
  ///
  /// In en, this message translates to:
  /// **'Check-in / check-out'**
  String get bookingsCheckInOut;

  /// No description provided for @bookingsPriceNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Price note (e.g. €120/night)'**
  String get bookingsPriceNoteLabel;

  /// No description provided for @bookingsSegmentFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From *'**
  String get bookingsSegmentFromLabel;

  /// No description provided for @bookingsSegmentToLabel.
  ///
  /// In en, this message translates to:
  /// **'To *'**
  String get bookingsSegmentToLabel;

  /// No description provided for @bookingsDepartureDate.
  ///
  /// In en, this message translates to:
  /// **'Departure date'**
  String get bookingsDepartureDate;

  /// No description provided for @bookingsSegmentProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider / carrier'**
  String get bookingsSegmentProviderLabel;

  /// No description provided for @bookingsSegmentUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Booking URL'**
  String get bookingsSegmentUrlLabel;

  /// No description provided for @bookingsNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get bookingsNotesLabel;

  /// No description provided for @bookingsModeFlight.
  ///
  /// In en, this message translates to:
  /// **'flight'**
  String get bookingsModeFlight;

  /// No description provided for @bookingsModeTrain.
  ///
  /// In en, this message translates to:
  /// **'train'**
  String get bookingsModeTrain;

  /// No description provided for @bookingsModeBus.
  ///
  /// In en, this message translates to:
  /// **'bus'**
  String get bookingsModeBus;

  /// No description provided for @bookingsModeCar.
  ///
  /// In en, this message translates to:
  /// **'car'**
  String get bookingsModeCar;

  /// No description provided for @bookingsModeFerry.
  ///
  /// In en, this message translates to:
  /// **'ferry'**
  String get bookingsModeFerry;

  /// No description provided for @bookingsModeOther.
  ///
  /// In en, this message translates to:
  /// **'other'**
  String get bookingsModeOther;

  /// No description provided for @budgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get budgetTitle;

  /// No description provided for @budgetEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No budget yet'**
  String get budgetEmptyTitle;

  /// No description provided for @budgetEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Set a target above, or add expenses below to track your spending.'**
  String get budgetEmptyMessage;

  /// No description provided for @budgetTargetSet.
  ///
  /// In en, this message translates to:
  /// **'Target: {amount} ({currency})'**
  String budgetTargetSet(String amount, String currency);

  /// No description provided for @budgetNoTarget.
  ///
  /// In en, this message translates to:
  /// **'No target set — tracking spend only'**
  String get budgetNoTarget;

  /// No description provided for @budgetEditExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get budgetEditExpenseTitle;

  /// No description provided for @budgetSetTargetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set budget target'**
  String get budgetSetTargetTitle;

  /// No description provided for @budgetCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get budgetCategoryLabel;

  /// No description provided for @budgetLabelField.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get budgetLabelField;

  /// No description provided for @budgetAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get budgetAmount;

  /// No description provided for @budgetCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get budgetCurrencyLabel;

  /// No description provided for @budgetTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get budgetTargetLabel;

  /// No description provided for @budgetTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank for none'**
  String get budgetTargetHint;

  /// No description provided for @budgetTargetHelp.
  ///
  /// In en, this message translates to:
  /// **'Leave the target blank to just track spending.'**
  String get budgetTargetHelp;

  /// No description provided for @budgetExpenseOptions.
  ///
  /// In en, this message translates to:
  /// **'Expense options'**
  String get budgetExpenseOptions;

  /// No description provided for @budgetMenuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get budgetMenuEdit;

  /// No description provided for @budgetTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total spent'**
  String get budgetTotalSpent;

  /// No description provided for @budgetRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get budgetRemaining;

  /// No description provided for @budgetAddHint.
  ///
  /// In en, this message translates to:
  /// **'Add an expense…'**
  String get budgetAddHint;

  /// No description provided for @budgetAddExpenseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get budgetAddExpenseTooltip;

  /// No description provided for @budgetCategoryFlights.
  ///
  /// In en, this message translates to:
  /// **'Flights'**
  String get budgetCategoryFlights;

  /// No description provided for @budgetCategoryLodging.
  ///
  /// In en, this message translates to:
  /// **'Lodging'**
  String get budgetCategoryLodging;

  /// No description provided for @budgetCategoryFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get budgetCategoryFood;

  /// No description provided for @budgetCategoryActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get budgetCategoryActivities;

  /// No description provided for @budgetCategoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get budgetCategoryTransport;

  /// No description provided for @budgetCategoryShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get budgetCategoryShopping;

  /// No description provided for @budgetCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get budgetCategoryGeneral;

  /// No description provided for @checklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Packing & prep'**
  String get checklistTitle;

  /// No description provided for @checklistEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing packed yet'**
  String get checklistEmptyTitle;

  /// No description provided for @checklistEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add items below, or ask the AI assistant to help build your list.'**
  String get checklistEmptyMessage;

  /// No description provided for @checklistEditItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get checklistEditItemTitle;

  /// No description provided for @checklistItemLabel.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get checklistItemLabel;

  /// No description provided for @checklistItemOptions.
  ///
  /// In en, this message translates to:
  /// **'Item options'**
  String get checklistItemOptions;

  /// No description provided for @checklistMenuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get checklistMenuEdit;

  /// No description provided for @checklistAddHint.
  ///
  /// In en, this message translates to:
  /// **'Add an item…'**
  String get checklistAddHint;

  /// No description provided for @checklistAddItemTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get checklistAddItemTooltip;

  /// No description provided for @checklistCategoryDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get checklistCategoryDocuments;

  /// No description provided for @checklistCategoryClothing.
  ///
  /// In en, this message translates to:
  /// **'Clothing'**
  String get checklistCategoryClothing;

  /// No description provided for @checklistCategoryElectronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get checklistCategoryElectronics;

  /// No description provided for @checklistCategoryHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get checklistCategoryHealth;

  /// No description provided for @checklistCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get checklistCategoryGeneral;

  /// No description provided for @itemDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add place'**
  String get itemDialogTitle;

  /// No description provided for @itemDialogSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search for a place'**
  String get itemDialogSearchLabel;

  /// No description provided for @itemDialogSearchHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Pastéis de Belém, Lisbon'**
  String get itemDialogSearchHint;

  /// No description provided for @itemDialogPickDifferent.
  ///
  /// In en, this message translates to:
  /// **'Pick a different place'**
  String get itemDialogPickDifferent;

  /// No description provided for @itemDialogAddManually.
  ///
  /// In en, this message translates to:
  /// **'Can\'t find it? Add manually'**
  String get itemDialogAddManually;

  /// No description provided for @itemDialogPlaceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Place name'**
  String get itemDialogPlaceNameLabel;

  /// No description provided for @itemDialogSearchInstead.
  ///
  /// In en, this message translates to:
  /// **'Search places instead'**
  String get itemDialogSearchInstead;

  /// No description provided for @itemDialogDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get itemDialogDayLabel;

  /// No description provided for @itemDialogUnscheduled.
  ///
  /// In en, this message translates to:
  /// **'Unscheduled'**
  String get itemDialogUnscheduled;

  /// No description provided for @itemDialogDayN.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String itemDialogDayN(int day);

  /// No description provided for @itemDialogNewDay.
  ///
  /// In en, this message translates to:
  /// **'New day ({day})'**
  String itemDialogNewDay(int day);

  /// No description provided for @itemDialogTimeOfDayLabel.
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get itemDialogTimeOfDayLabel;

  /// No description provided for @itemDialogTimeAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get itemDialogTimeAny;

  /// No description provided for @itemDialogTimeMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get itemDialogTimeMorning;

  /// No description provided for @itemDialogTimeAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get itemDialogTimeAfternoon;

  /// No description provided for @itemDialogTimeEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get itemDialogTimeEvening;

  /// No description provided for @itemDialogCategoryAttraction.
  ///
  /// In en, this message translates to:
  /// **'Attraction'**
  String get itemDialogCategoryAttraction;

  /// No description provided for @itemDialogCategoryRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get itemDialogCategoryRestaurant;

  /// No description provided for @itemDialogAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get itemDialogAdd;

  /// No description provided for @itemDialogNoResults.
  ///
  /// In en, this message translates to:
  /// **'No places found — try a different search, or add the place manually.'**
  String get itemDialogNoResults;

  /// No description provided for @itemDialogSearchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Search unavailable — add the place manually below.'**
  String get itemDialogSearchUnavailable;

  /// No description provided for @itemDialogErrorEnterName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for the place.'**
  String get itemDialogErrorEnterName;

  /// No description provided for @itemDialogErrorPickPlace.
  ///
  /// In en, this message translates to:
  /// **'Pick a place first.'**
  String get itemDialogErrorPickPlace;

  /// No description provided for @itemDialogErrorAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add the place: {error}'**
  String itemDialogErrorAddFailed(String error);

  /// No description provided for @commonOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — reconnect to make changes.'**
  String get commonOffline;

  /// No description provided for @commonGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get commonGenericError;

  /// No description provided for @tripTitleFallback.
  ///
  /// In en, this message translates to:
  /// **'Trip'**
  String get tripTitleFallback;

  /// No description provided for @tripOtherPlaces.
  ///
  /// In en, this message translates to:
  /// **'Other places'**
  String get tripOtherPlaces;

  /// No description provided for @tripOfflineGuard.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — reconnect to make changes.'**
  String get tripOfflineGuard;

  /// No description provided for @tripTravelModeDriving.
  ///
  /// In en, this message translates to:
  /// **'Driving'**
  String get tripTravelModeDriving;

  /// No description provided for @tripTravelModeByTrain.
  ///
  /// In en, this message translates to:
  /// **'By train'**
  String get tripTravelModeByTrain;

  /// No description provided for @tripTravelModeByBus.
  ///
  /// In en, this message translates to:
  /// **'By bus'**
  String get tripTravelModeByBus;

  /// No description provided for @tripTravelModeByFerry.
  ///
  /// In en, this message translates to:
  /// **'By ferry'**
  String get tripTravelModeByFerry;

  /// No description provided for @tripTravelModeMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed modes'**
  String get tripTravelModeMixed;

  /// No description provided for @tripTravelModeFlying.
  ///
  /// In en, this message translates to:
  /// **'Flying'**
  String get tripTravelModeFlying;

  /// No description provided for @tripTravelModeUnset.
  ///
  /// In en, this message translates to:
  /// **'Travel mode'**
  String get tripTravelModeUnset;

  /// No description provided for @tripTravelModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Travel mode'**
  String get tripTravelModeTooltip;

  /// No description provided for @tripModeTrain.
  ///
  /// In en, this message translates to:
  /// **'Train'**
  String get tripModeTrain;

  /// No description provided for @tripModeBus.
  ///
  /// In en, this message translates to:
  /// **'Bus'**
  String get tripModeBus;

  /// No description provided for @tripModeFerry.
  ///
  /// In en, this message translates to:
  /// **'Ferry'**
  String get tripModeFerry;

  /// No description provided for @tripUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String tripUpdateFailed(String error);

  /// No description provided for @tripDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String tripDeleteFailed(String error);

  /// No description provided for @tripReorderFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reorder: {error}'**
  String tripReorderFailed(String error);

  /// No description provided for @tripLeaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove trip: {error}'**
  String tripLeaveFailed(String error);

  /// No description provided for @tripAddStayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add stay: {error}'**
  String tripAddStayFailed(String error);

  /// No description provided for @tripRemoveStayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove stay: {error}'**
  String tripRemoveStayFailed(String error);

  /// No description provided for @tripUpdateStayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update stay: {error}'**
  String tripUpdateStayFailed(String error);

  /// No description provided for @tripKeepStayFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not keep stay: {error}'**
  String tripKeepStayFailed(String error);

  /// No description provided for @tripAddTransportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add transport: {error}'**
  String tripAddTransportFailed(String error);

  /// No description provided for @tripRemoveTransportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove transport: {error}'**
  String tripRemoveTransportFailed(String error);

  /// No description provided for @tripUpdateTransportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update transport: {error}'**
  String tripUpdateTransportFailed(String error);

  /// No description provided for @tripKeepTransportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not keep transport: {error}'**
  String tripKeepTransportFailed(String error);

  /// No description provided for @tripShareLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create share link: {error}'**
  String tripShareLinkFailed(String error);

  /// No description provided for @tripPrintExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the printable view: {error}'**
  String tripPrintExportFailed(String error);

  /// No description provided for @tripCalendarExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the calendar: {error}'**
  String tripCalendarExportFailed(String error);

  /// No description provided for @tripEventExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export the event: {error}'**
  String tripEventExportFailed(String error);

  /// No description provided for @tripSharingOffFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not turn off sharing: {error}'**
  String tripSharingOffFailed(String error);

  /// No description provided for @tripInviteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create invite: {error}'**
  String tripInviteFailed(String error);

  /// No description provided for @tripRemoveItemFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove {name}: {error}'**
  String tripRemoveItemFailed(String name, String error);

  /// No description provided for @tripRestoreItemFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore {name}: {error}'**
  String tripRestoreItemFailed(String name, String error);

  /// No description provided for @tripUpdateItemFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update {name}: {error}'**
  String tripUpdateItemFailed(String name, String error);

  /// No description provided for @tripMoveItemFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not move item: {error}'**
  String tripMoveItemFailed(String error);

  /// No description provided for @tripUpdateBookingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update booking: {error}'**
  String tripUpdateBookingFailed(String error);

  /// No description provided for @tripUndoFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not undo: {error}'**
  String tripUndoFailed(String error);

  /// No description provided for @tripAddPackingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add packing item: {error}'**
  String tripAddPackingFailed(String error);

  /// No description provided for @tripLoadBudgetFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load budget: {error}'**
  String tripLoadBudgetFailed(String error);

  /// No description provided for @tripUpdateBudgetFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update budget: {error}'**
  String tripUpdateBudgetFailed(String error);

  /// No description provided for @tripSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String tripSaveFailed(String error);

  /// No description provided for @tripOpenLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get tripOpenLinkFailed;

  /// No description provided for @tripFerrySearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open ferry search'**
  String get tripFerrySearchFailed;

  /// No description provided for @tripLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load this trip'**
  String get tripLoadFailed;

  /// No description provided for @tripEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit title'**
  String get tripEditTitle;

  /// No description provided for @tripDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete trip?'**
  String get tripDeleteTitle;

  /// No description provided for @tripDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get tripDeleteBody;

  /// No description provided for @tripLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from my trips?'**
  String get tripLeaveTitle;

  /// No description provided for @tripLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose access until you\'re invited again. The trip itself is not deleted.'**
  String get tripLeaveBody;

  /// No description provided for @tripRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get tripRemove;

  /// No description provided for @tripUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get tripUndo;

  /// No description provided for @tripAddPlacesBeforeRefine.
  ///
  /// In en, this message translates to:
  /// **'Add some places before refining with AI.'**
  String get tripAddPlacesBeforeRefine;

  /// No description provided for @tripAssistantLabel.
  ///
  /// In en, this message translates to:
  /// **'Trip assistant'**
  String get tripAssistantLabel;

  /// No description provided for @tripRefiningSection.
  ///
  /// In en, this message translates to:
  /// **'Refining {section}'**
  String tripRefiningSection(String section);

  /// No description provided for @tripRefineCity.
  ///
  /// In en, this message translates to:
  /// **'Refine {city}'**
  String tripRefineCity(String city);

  /// No description provided for @tripRefineThisDay.
  ///
  /// In en, this message translates to:
  /// **'Refine this day'**
  String get tripRefineThisDay;

  /// No description provided for @tripRefineWithAI.
  ///
  /// In en, this message translates to:
  /// **'Refine with AI'**
  String get tripRefineWithAI;

  /// No description provided for @tripAskAI.
  ///
  /// In en, this message translates to:
  /// **'Ask AI about this trip'**
  String get tripAskAI;

  /// No description provided for @tripShareLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Share link copied to clipboard'**
  String get tripShareLinkCopied;

  /// No description provided for @tripSharingTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'Sharing turned off — links no longer work (existing co-planners and followers keep access)'**
  String get tripSharingTurnedOff;

  /// No description provided for @tripCoPlanInviteMessage.
  ///
  /// In en, this message translates to:
  /// **'Co-plan with me: {summary}'**
  String tripCoPlanInviteMessage(String summary);

  /// No description provided for @tripInviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Co-planner invite copied — anyone with it can edit'**
  String get tripInviteCopied;

  /// No description provided for @tripCoPlannerRemoved.
  ///
  /// In en, this message translates to:
  /// **'Co-planner removed'**
  String get tripCoPlannerRemoved;

  /// No description provided for @tripInviteSent.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {email}'**
  String tripInviteSent(String email);

  /// No description provided for @tripShareTrip.
  ///
  /// In en, this message translates to:
  /// **'Share trip'**
  String get tripShareTrip;

  /// No description provided for @tripShareLinkAction.
  ///
  /// In en, this message translates to:
  /// **'Share link…'**
  String get tripShareLinkAction;

  /// No description provided for @tripCopyShareLink.
  ///
  /// In en, this message translates to:
  /// **'Copy share link'**
  String get tripCopyShareLink;

  /// No description provided for @tripShareInviteAction.
  ///
  /// In en, this message translates to:
  /// **'Share co-planner invite…'**
  String get tripShareInviteAction;

  /// No description provided for @tripCopyInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link (can edit)'**
  String get tripCopyInviteLink;

  /// No description provided for @tripManageAccess.
  ///
  /// In en, this message translates to:
  /// **'Manage access'**
  String get tripManageAccess;

  /// No description provided for @tripPrintSavePdf.
  ///
  /// In en, this message translates to:
  /// **'Print / Save as PDF'**
  String get tripPrintSavePdf;

  /// No description provided for @tripAddToCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add to calendar'**
  String get tripAddToCalendar;

  /// No description provided for @tripTurnOffSharing.
  ///
  /// In en, this message translates to:
  /// **'Turn off sharing'**
  String get tripTurnOffSharing;

  /// No description provided for @tripDeleteTrip.
  ///
  /// In en, this message translates to:
  /// **'Delete trip'**
  String get tripDeleteTrip;

  /// No description provided for @tripRemoveFromMyTrips.
  ///
  /// In en, this message translates to:
  /// **'Remove from my trips'**
  String get tripRemoveFromMyTrips;

  /// No description provided for @tripLocalIntel.
  ///
  /// In en, this message translates to:
  /// **'Local intel'**
  String get tripLocalIntel;

  /// No description provided for @tripLocalGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Local guide: {title}'**
  String tripLocalGuideTitle(String title);

  /// No description provided for @tripGuideBy.
  ///
  /// In en, this message translates to:
  /// **'By {name}'**
  String tripGuideBy(String name);

  /// No description provided for @tripEventsWhileHere.
  ///
  /// In en, this message translates to:
  /// **'Events while you\'re here'**
  String get tripEventsWhileHere;

  /// No description provided for @tripFindingEvents.
  ///
  /// In en, this message translates to:
  /// **'Finding events in {city}…'**
  String tripFindingEvents(String city);

  /// No description provided for @tripFindEventsIn.
  ///
  /// In en, this message translates to:
  /// **'Find events in {city}'**
  String tripFindEventsIn(String city);

  /// No description provided for @tripRecommendedBy.
  ///
  /// In en, this message translates to:
  /// **'Recommended by {name}'**
  String tripRecommendedBy(String name);

  /// No description provided for @tripFindFlights.
  ///
  /// In en, this message translates to:
  /// **'Find flights'**
  String get tripFindFlights;

  /// No description provided for @tripFindFerries.
  ///
  /// In en, this message translates to:
  /// **'Find ferries'**
  String get tripFindFerries;

  /// No description provided for @tripAddBooking.
  ///
  /// In en, this message translates to:
  /// **'Add a booking'**
  String get tripAddBooking;

  /// No description provided for @tripEditBooking.
  ///
  /// In en, this message translates to:
  /// **'Edit booking'**
  String get tripEditBooking;

  /// No description provided for @tripFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get tripFieldType;

  /// No description provided for @tripKindStay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get tripKindStay;

  /// No description provided for @tripKindTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get tripKindTransport;

  /// No description provided for @tripKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get tripKindOther;

  /// No description provided for @tripFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get tripFieldTitle;

  /// No description provided for @tripFieldOrigin.
  ///
  /// In en, this message translates to:
  /// **'Origin (optional)'**
  String get tripFieldOrigin;

  /// No description provided for @tripFieldDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination (optional)'**
  String get tripFieldDestination;

  /// No description provided for @tripFieldDepartDate.
  ///
  /// In en, this message translates to:
  /// **'Depart date (optional)'**
  String get tripFieldDepartDate;

  /// No description provided for @tripFieldCheckIn.
  ///
  /// In en, this message translates to:
  /// **'Check-in (optional)'**
  String get tripFieldCheckIn;

  /// No description provided for @tripFieldCheckOut.
  ///
  /// In en, this message translates to:
  /// **'Check-out (optional)'**
  String get tripFieldCheckOut;

  /// No description provided for @tripFieldLink.
  ///
  /// In en, this message translates to:
  /// **'Link (optional, overrides search)'**
  String get tripFieldLink;

  /// No description provided for @tripTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get tripTitleRequired;

  /// No description provided for @tripClearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get tripClearDate;

  /// No description provided for @tripItinerary.
  ///
  /// In en, this message translates to:
  /// **'Itinerary'**
  String get tripItinerary;

  /// No description provided for @tripToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get tripToday;

  /// No description provided for @tripAddPlace.
  ///
  /// In en, this message translates to:
  /// **'Add place'**
  String get tripAddPlace;

  /// No description provided for @tripFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tripFilterAll;

  /// No description provided for @tripFilterAttractions.
  ///
  /// In en, this message translates to:
  /// **'Attractions'**
  String get tripFilterAttractions;

  /// No description provided for @tripFilterRestaurants.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get tripFilterRestaurants;

  /// No description provided for @tripFilterNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No places match this filter.'**
  String get tripFilterNoMatch;

  /// No description provided for @tripNoPlacesYet.
  ///
  /// In en, this message translates to:
  /// **'No places yet'**
  String get tripNoPlacesYet;

  /// No description provided for @tripNoPlacesYetMessage.
  ///
  /// In en, this message translates to:
  /// **'Refine with AI or add a place to start your itinerary.'**
  String get tripNoPlacesYetMessage;

  /// No description provided for @tripNoMappedPlaces.
  ///
  /// In en, this message translates to:
  /// **'No mapped places'**
  String get tripNoMappedPlaces;

  /// No description provided for @tripNoPlacesOnDay.
  ///
  /// In en, this message translates to:
  /// **'No places pinned on Day {day}'**
  String tripNoPlacesOnDay(int day);

  /// No description provided for @tripAddPlaceMapHint.
  ///
  /// In en, this message translates to:
  /// **'Add a place to see it on the map.'**
  String get tripAddPlaceMapHint;

  /// No description provided for @tripDayN.
  ///
  /// In en, this message translates to:
  /// **'Day {n}'**
  String tripDayN(int n);

  /// No description provided for @tripDayTripTo.
  ///
  /// In en, this message translates to:
  /// **'Day trip · {town}'**
  String tripDayTripTo(String town);

  /// No description provided for @tripDayTripFallback.
  ///
  /// In en, this message translates to:
  /// **'Day trip'**
  String get tripDayTripFallback;

  /// No description provided for @tripTonight.
  ///
  /// In en, this message translates to:
  /// **'Tonight: {stays}'**
  String tripTonight(String stays);

  /// No description provided for @tripTravelMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String tripTravelMinutes(int minutes);

  /// No description provided for @tripTravelHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String tripTravelHours(int hours);

  /// No description provided for @tripTravelHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String tripTravelHoursMinutes(int hours, int minutes);

  /// No description provided for @tripTravelFromHub.
  ///
  /// In en, this message translates to:
  /// **'{duration} from {hub}'**
  String tripTravelFromHub(String duration, String hub);

  /// No description provided for @tripTravelTotal.
  ///
  /// In en, this message translates to:
  /// **'{duration} travel'**
  String tripTravelTotal(String duration);

  /// No description provided for @tripRainChance.
  ///
  /// In en, this message translates to:
  /// **'{percent}% rain'**
  String tripRainChance(int percent);

  /// No description provided for @tripTypicalForDates.
  ///
  /// In en, this message translates to:
  /// **'typical for these dates'**
  String get tripTypicalForDates;

  /// No description provided for @tripPlaceActions.
  ///
  /// In en, this message translates to:
  /// **'Place actions'**
  String get tripPlaceActions;

  /// No description provided for @tripOpenInGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps'**
  String get tripOpenInGoogleMaps;

  /// No description provided for @tripEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get tripEdit;

  /// No description provided for @tripMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get tripMoveUp;

  /// No description provided for @tripMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get tripMoveDown;

  /// No description provided for @tripReorderSection.
  ///
  /// In en, this message translates to:
  /// **'Reorder section'**
  String get tripReorderSection;

  /// No description provided for @tripAddToGoogleCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add to Google Calendar'**
  String get tripAddToGoogleCalendar;

  /// No description provided for @tripAddToAppleCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add to Apple Calendar (.ics)'**
  String get tripAddToAppleCalendar;

  /// No description provided for @tripRemovedItem.
  ///
  /// In en, this message translates to:
  /// **'Removed {name}'**
  String tripRemovedItem(String name);

  /// No description provided for @tripMovedToDay.
  ///
  /// In en, this message translates to:
  /// **'Moved to Day {day}'**
  String tripMovedToDay(int day);

  /// No description provided for @tripMarkedAsBooked.
  ///
  /// In en, this message translates to:
  /// **'Marked as booked'**
  String get tripMarkedAsBooked;

  /// No description provided for @tripAddedToPacking.
  ///
  /// In en, this message translates to:
  /// **'Added \"{item}\" to packing'**
  String tripAddedToPacking(String item);

  /// No description provided for @tripSetBudgetTarget.
  ///
  /// In en, this message translates to:
  /// **'Set budget target'**
  String get tripSetBudgetTarget;

  /// No description provided for @tripBudgetTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target ({currency})'**
  String tripBudgetTargetLabel(String currency);

  /// No description provided for @tripBudgetTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to just track spending'**
  String get tripBudgetTargetHint;

  /// No description provided for @tripRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get tripRename;

  /// No description provided for @tripAddDates.
  ///
  /// In en, this message translates to:
  /// **'Add dates'**
  String get tripAddDates;

  /// No description provided for @tripChangeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change status'**
  String get tripChangeStatus;

  /// No description provided for @tripStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get tripStatusDraft;

  /// No description provided for @tripStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get tripStatusPlanned;

  /// No description provided for @tripCoPlanningWith.
  ///
  /// In en, this message translates to:
  /// **'Co-planning with {name} — your changes save for everyone.'**
  String tripCoPlanningWith(String name);

  /// No description provided for @tripCoPlanningShared.
  ///
  /// In en, this message translates to:
  /// **'Co-planning a shared trip — your changes save for everyone.'**
  String get tripCoPlanningShared;

  /// No description provided for @tripSharedBy.
  ///
  /// In en, this message translates to:
  /// **'Shared by {name} — view only.'**
  String tripSharedBy(String name);

  /// No description provided for @tripSharedViewOnly.
  ///
  /// In en, this message translates to:
  /// **'Shared trip — view only.'**
  String get tripSharedViewOnly;

  /// No description provided for @tripUpdatedBy.
  ///
  /// In en, this message translates to:
  /// **'Updated by {name} · {time}'**
  String tripUpdatedBy(String name, String time);

  /// No description provided for @tripOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tripOverview;

  /// No description provided for @tripShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get tripShowMore;

  /// No description provided for @tripShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get tripShowLess;

  /// No description provided for @tripTimeRecently.
  ///
  /// In en, this message translates to:
  /// **'recently'**
  String get tripTimeRecently;

  /// No description provided for @tripTimeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get tripTimeJustNow;

  /// No description provided for @tripTimeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String tripTimeMinutesAgo(int minutes);

  /// No description provided for @tripTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String tripTimeHoursAgo(int hours);

  /// No description provided for @tripTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String tripTimeDaysAgo(int days);

  /// No description provided for @tripFriendEmail.
  ///
  /// In en, this message translates to:
  /// **'Friend\'s email'**
  String get tripFriendEmail;

  /// No description provided for @tripInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get tripInvite;

  /// No description provided for @tripNoCoPlanners.
  ///
  /// In en, this message translates to:
  /// **'No co-planners yet. Invite a friend by email above, or copy an invite link from the share menu.'**
  String get tripNoCoPlanners;

  /// No description provided for @tripRoleViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get tripRoleViewer;

  /// No description provided for @tripRoleCanEdit.
  ///
  /// In en, this message translates to:
  /// **'Can edit'**
  String get tripRoleCanEdit;

  /// No description provided for @tripRemoveAccess.
  ///
  /// In en, this message translates to:
  /// **'Remove access'**
  String get tripRemoveAccess;

  /// No description provided for @tripPendingInvites.
  ///
  /// In en, this message translates to:
  /// **'Pending invites'**
  String get tripPendingInvites;

  /// No description provided for @tripInvited.
  ///
  /// In en, this message translates to:
  /// **'Invited — {expires}'**
  String tripInvited(String expires);

  /// No description provided for @tripRevokeInvite.
  ///
  /// In en, this message translates to:
  /// **'Revoke invite'**
  String get tripRevokeInvite;

  /// No description provided for @tripExpiresInDays.
  ///
  /// In en, this message translates to:
  /// **'expires in {days}d'**
  String tripExpiresInDays(int days);

  /// No description provided for @tripExpiresInHours.
  ///
  /// In en, this message translates to:
  /// **'expires in {hours}h'**
  String tripExpiresInHours(int hours);

  /// No description provided for @tripExpiresSoon.
  ///
  /// In en, this message translates to:
  /// **'expires soon'**
  String get tripExpiresSoon;

  /// No description provided for @tripEditPlace.
  ///
  /// In en, this message translates to:
  /// **'Edit place'**
  String get tripEditPlace;

  /// No description provided for @tripFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tripFieldName;

  /// No description provided for @tripFieldCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get tripFieldCity;

  /// No description provided for @tripFieldDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get tripFieldDay;

  /// No description provided for @tripCategoryAttraction.
  ///
  /// In en, this message translates to:
  /// **'Attraction'**
  String get tripCategoryAttraction;

  /// No description provided for @tripCategoryRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get tripCategoryRestaurant;

  /// No description provided for @tripTimeMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get tripTimeMorning;

  /// No description provided for @tripTimeAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get tripTimeAfternoon;

  /// No description provided for @tripTimeEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get tripTimeEvening;

  /// No description provided for @tripReorderPlaces.
  ///
  /// In en, this message translates to:
  /// **'Reorder places'**
  String get tripReorderPlaces;

  /// No description provided for @tripReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to change the visit order within this section.'**
  String get tripReorderHint;

  /// No description provided for @tripSaveOrder.
  ///
  /// In en, this message translates to:
  /// **'Save order'**
  String get tripSaveOrder;

  /// No description provided for @tripsListTitle.
  ///
  /// In en, this message translates to:
  /// **'My Trips'**
  String get tripsListTitle;

  /// No description provided for @tripsListErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load trips'**
  String get tripsListErrorTitle;

  /// No description provided for @tripsListErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get tripsListErrorMessage;

  /// No description provided for @tripsListEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No trips yet'**
  String get tripsListEmptyTitle;

  /// No description provided for @tripsListEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Chat with the AI agent to create your first trip.'**
  String get tripsListEmptyMessage;

  /// No description provided for @tripsListPlanTrip.
  ///
  /// In en, this message translates to:
  /// **'Plan a trip'**
  String get tripsListPlanTrip;

  /// No description provided for @tripsListSharedWithYou.
  ///
  /// In en, this message translates to:
  /// **'Shared with you'**
  String get tripsListSharedWithYou;

  /// No description provided for @tripsListCreated.
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String tripsListCreated(String date);

  /// No description provided for @tripsListPlannedWith.
  ///
  /// In en, this message translates to:
  /// **'Planned with {name}'**
  String tripsListPlannedWith(String name);

  /// No description provided for @tripsListSharedBy.
  ///
  /// In en, this message translates to:
  /// **'Shared by {name}'**
  String tripsListSharedBy(String name);

  /// No description provided for @tripsListVersionsError.
  ///
  /// In en, this message translates to:
  /// **'Could not load versions'**
  String get tripsListVersionsError;

  /// No description provided for @tripsListVersionLatest.
  ///
  /// In en, this message translates to:
  /// **'latest · {date}'**
  String tripsListVersionLatest(String date);

  /// No description provided for @tripsListVersionNumbered.
  ///
  /// In en, this message translates to:
  /// **'v{version} · {date}'**
  String tripsListVersionNumbered(int version, String date);

  /// No description provided for @homeGreetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get homeGreetingMorning;

  /// No description provided for @homeGreetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get homeGreetingAfternoon;

  /// No description provided for @homeGreetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get homeGreetingEvening;

  /// No description provided for @homeGreetingNamed.
  ///
  /// In en, this message translates to:
  /// **'{greeting}, {name}'**
  String homeGreetingNamed(String greeting, String name);

  /// No description provided for @homeGreetingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where are we off to next?'**
  String get homeGreetingSubtitle;

  /// No description provided for @homeHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan less. Travel more.'**
  String get homeHeroTitle;

  /// No description provided for @homeHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Describe the trip you\'re dreaming of and I\'ll build the full itinerary — places, days, and routes.'**
  String get homeHeroSubtitle;

  /// No description provided for @homeHeroCta.
  ///
  /// In en, this message translates to:
  /// **'Let\'s go'**
  String get homeHeroCta;

  /// No description provided for @homeSuggestionParis.
  ///
  /// In en, this message translates to:
  /// **'2 days in Paris'**
  String get homeSuggestionParis;

  /// No description provided for @homeSuggestionRome.
  ///
  /// In en, this message translates to:
  /// **'Museums in Rome'**
  String get homeSuggestionRome;

  /// No description provided for @homeSuggestionTokyo.
  ///
  /// In en, this message translates to:
  /// **'Weekend in Tokyo'**
  String get homeSuggestionTokyo;

  /// No description provided for @homeStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get homeStatusDraft;

  /// No description provided for @homeStatusPlanned.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get homeStatusPlanned;

  /// No description provided for @homeRecentTripEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PICK UP WHERE YOU LEFT OFF'**
  String get homeRecentTripEyebrow;

  /// No description provided for @homeLocalGuidesTitle.
  ///
  /// In en, this message translates to:
  /// **'Local guides'**
  String get homeLocalGuidesTitle;

  /// No description provided for @homeGuideByline.
  ///
  /// In en, this message translates to:
  /// **'By {name}'**
  String homeGuideByline(String name);

  /// No description provided for @shellNavHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get shellNavHome;

  /// No description provided for @shellNavPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get shellNavPlan;

  /// No description provided for @shellNavTrips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get shellNavTrips;

  /// No description provided for @healthMetricsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load metrics'**
  String get healthMetricsErrorTitle;

  /// No description provided for @healthHealthErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load health'**
  String get healthHealthErrorTitle;

  /// No description provided for @healthProcessSection.
  ///
  /// In en, this message translates to:
  /// **'Process'**
  String get healthProcessSection;

  /// No description provided for @healthRoutesSection.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get healthRoutesSection;

  /// No description provided for @healthUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime'**
  String get healthUptime;

  /// No description provided for @healthRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get healthRequests;

  /// No description provided for @healthErrorRate.
  ///
  /// In en, this message translates to:
  /// **'Error rate'**
  String get healthErrorRate;

  /// No description provided for @healthGoroutines.
  ///
  /// In en, this message translates to:
  /// **'Goroutines'**
  String get healthGoroutines;

  /// No description provided for @healthMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get healthMemory;

  /// No description provided for @healthPlacesCalls.
  ///
  /// In en, this message translates to:
  /// **'Places calls'**
  String get healthPlacesCalls;

  /// No description provided for @healthCacheHits.
  ///
  /// In en, this message translates to:
  /// **'{count} cache hits'**
  String healthCacheHits(int count);

  /// No description provided for @healthColRoute.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get healthColRoute;

  /// No description provided for @healthColMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get healthColMethod;

  /// No description provided for @healthColCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get healthColCount;

  /// No description provided for @healthColErrorPct.
  ///
  /// In en, this message translates to:
  /// **'Error %'**
  String get healthColErrorPct;

  /// No description provided for @healthDependenciesSection.
  ///
  /// In en, this message translates to:
  /// **'Dependencies'**
  String get healthDependenciesSection;

  /// No description provided for @healthDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get healthDatabase;

  /// No description provided for @healthPing.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms ping'**
  String healthPing(int ms);

  /// No description provided for @healthPillOk.
  ///
  /// In en, this message translates to:
  /// **'ok'**
  String get healthPillOk;

  /// No description provided for @healthPillUnreachable.
  ///
  /// In en, this message translates to:
  /// **'unreachable'**
  String get healthPillUnreachable;

  /// No description provided for @healthPillConfigured.
  ///
  /// In en, this message translates to:
  /// **'configured'**
  String get healthPillConfigured;

  /// No description provided for @healthPillNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'not configured'**
  String get healthPillNotConfigured;

  /// No description provided for @healthPillUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get healthPillUnknown;

  /// No description provided for @healthPillStale.
  ///
  /// In en, this message translates to:
  /// **'stale'**
  String get healthPillStale;

  /// No description provided for @healthPillFresh.
  ///
  /// In en, this message translates to:
  /// **'fresh'**
  String get healthPillFresh;

  /// No description provided for @healthBackupsSection.
  ///
  /// In en, this message translates to:
  /// **'Backups'**
  String get healthBackupsSection;

  /// No description provided for @healthLastBackup.
  ///
  /// In en, this message translates to:
  /// **'Last backup'**
  String get healthLastBackup;

  /// No description provided for @healthBackupAge.
  ///
  /// In en, this message translates to:
  /// **'{age} ago'**
  String healthBackupAge(String age);

  /// No description provided for @healthNoBackupRecorded.
  ///
  /// In en, this message translates to:
  /// **'no backup recorded'**
  String get healthNoBackupRecorded;

  /// No description provided for @healthBuildSection.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get healthBuildSection;

  /// No description provided for @healthRelease.
  ///
  /// In en, this message translates to:
  /// **'release {release}'**
  String healthRelease(String release);

  /// No description provided for @healthDegradedTitle.
  ///
  /// In en, this message translates to:
  /// **'System degraded'**
  String get healthDegradedTitle;

  /// No description provided for @reviewSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip health'**
  String get reviewSectionTitle;

  /// No description provided for @reviewCountToReview.
  ///
  /// In en, this message translates to:
  /// **'{count} to review'**
  String reviewCountToReview(int count);

  /// No description provided for @reviewEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Looks good'**
  String get reviewEmptyTitle;

  /// No description provided for @reviewEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'No issues found — your trip is in good shape.'**
  String get reviewEmptyMessage;

  /// No description provided for @reviewSeverityCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get reviewSeverityCritical;

  /// No description provided for @reviewSeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get reviewSeverityWarning;

  /// No description provided for @reviewSeverityInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get reviewSeverityInfo;

  /// No description provided for @reviewOfflineSnack.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — reconnect to run more checks.'**
  String get reviewOfflineSnack;

  /// No description provided for @reviewHoursChecked.
  ///
  /// In en, this message translates to:
  /// **'Opening hours checked'**
  String get reviewHoursChecked;

  /// No description provided for @reviewCheckHours.
  ///
  /// In en, this message translates to:
  /// **'Also check opening hours'**
  String get reviewCheckHours;

  /// No description provided for @liveTripEyebrow.
  ///
  /// In en, this message translates to:
  /// **'HAPPENING NOW'**
  String get liveTripEyebrow;

  /// No description provided for @liveTripStatusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get liveTripStatusLive;

  /// No description provided for @liveTripDay.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String liveTripDay(int day);

  /// No description provided for @liveTripDayOfTotal.
  ///
  /// In en, this message translates to:
  /// **'Day {day} of {total}'**
  String liveTripDayOfTotal(int day, int total);

  /// No description provided for @continueChatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue where you left off'**
  String get continueChatsTitle;

  /// No description provided for @continueChatsReopenError.
  ///
  /// In en, this message translates to:
  /// **'Could not reopen that conversation.'**
  String get continueChatsReopenError;

  /// No description provided for @continueChatsDismissError.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss that conversation.'**
  String get continueChatsDismissError;

  /// No description provided for @continueChatsDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get continueChatsDismiss;

  /// No description provided for @mapNoMappedPlaces.
  ///
  /// In en, this message translates to:
  /// **'No mapped places'**
  String get mapNoMappedPlaces;

  /// No description provided for @mapZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get mapZoomIn;

  /// No description provided for @mapZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get mapZoomOut;

  /// No description provided for @mapResetMap.
  ///
  /// In en, this message translates to:
  /// **'Reset map'**
  String get mapResetMap;

  /// No description provided for @accountMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountMenuTooltip;

  /// No description provided for @accountMenuTravelProfile.
  ///
  /// In en, this message translates to:
  /// **'Travel profile'**
  String get accountMenuTravelProfile;

  /// No description provided for @accountMenuPriceAlerts.
  ///
  /// In en, this message translates to:
  /// **'Price alerts'**
  String get accountMenuPriceAlerts;

  /// No description provided for @accountMenuRetakeQuiz.
  ///
  /// In en, this message translates to:
  /// **'Retake travel quiz'**
  String get accountMenuRetakeQuiz;

  /// No description provided for @accountMenuAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get accountMenuAccountSettings;

  /// No description provided for @accountMenuLocalIntelAdmin.
  ///
  /// In en, this message translates to:
  /// **'Local intel admin'**
  String get accountMenuLocalIntelAdmin;

  /// No description provided for @accountMenuMetrics.
  ///
  /// In en, this message translates to:
  /// **'Metrics'**
  String get accountMenuMetrics;

  /// No description provided for @accountMenuSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountMenuSignOut;
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
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
