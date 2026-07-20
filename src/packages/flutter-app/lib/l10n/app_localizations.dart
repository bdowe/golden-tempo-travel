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
