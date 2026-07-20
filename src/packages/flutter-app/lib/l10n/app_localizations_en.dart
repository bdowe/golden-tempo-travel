// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Golden Tempo Travel';

  @override
  String get languageSectionTitle => 'Language';

  @override
  String get languageSystemDefault => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageChangeNote =>
      'Trips and notes you already saved stay in the language they were written in.';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSeeAll => 'See all';

  @override
  String citiesTwo(String first, String second) {
    return '$first & $second';
  }

  @override
  String citiesMore(String first, String second, int count) {
    return '$first & $second +$count more';
  }

  @override
  String get prefsTitle => 'Travel profile';

  @override
  String get prefsBudget => 'Budget';

  @override
  String get prefsPace => 'Pace';

  @override
  String get prefsInterests => 'Interests';

  @override
  String get prefsAddInterest => 'Add an interest';

  @override
  String get prefsHomeAirport => 'Home airport';

  @override
  String get prefsHomeAirportHelp =>
      'Used as the default origin when planning flights.';

  @override
  String get prefsProfileNotes => 'Profile notes';

  @override
  String get prefsProfileNotesHelp =>
      'Your AI agent keeps these notes as it learns about you. Edit or clear them anytime.';

  @override
  String get prefsProfileNotesHint =>
      'Nothing noted yet — the agent adds to this as you plan trips.';

  @override
  String get prefsSaved => 'Preferences saved';

  @override
  String get prefsSaveFailed => 'Could not save preferences';

  @override
  String get prefsBudgetLow => 'budget';

  @override
  String get prefsBudgetMid => 'mid';

  @override
  String get prefsBudgetLuxury => 'luxury';

  @override
  String get prefsPaceRelaxed => 'relaxed';

  @override
  String get prefsPaceBalanced => 'balanced';

  @override
  String get prefsPacePacked => 'packed';

  @override
  String get prefsInterestMuseums => 'museums';

  @override
  String get prefsInterestFood => 'food';

  @override
  String get prefsInterestNightlife => 'nightlife';

  @override
  String get prefsInterestNature => 'nature';

  @override
  String get prefsInterestHistory => 'history';

  @override
  String get prefsInterestArt => 'art';

  @override
  String get prefsInterestShopping => 'shopping';

  @override
  String get prefsInterestOutdoors => 'outdoors';

  @override
  String get prefsInterestBeaches => 'beaches';

  @override
  String get prefsInterestArchitecture => 'architecture';

  @override
  String get ssoContinueWithGoogle => 'Continue with Google';

  @override
  String get ssoContinueWithApple => 'Continue with Apple';

  @override
  String get ssoDividerOr => 'or';

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get authCreateAccountTitle => 'Create your account';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authEmailRequired => 'Email is required';

  @override
  String get authEmailInvalid => 'Enter a valid email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordRequired => 'Password is required';

  @override
  String get authPasswordTooShort => 'Password must be at least 8 characters';

  @override
  String get authDisplayNameLabel => 'Display name (optional)';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authNoAccountPrompt => 'Don\'t have an account? Sign up';

  @override
  String get authHaveAccountPrompt => 'Already have an account? Sign in';

  @override
  String get authForgotPassword => 'Forgot password?';

  @override
  String get authPasswordUpdatedSnack =>
      'Password updated — sign in with your new password';

  @override
  String get authResetDialogTitle => 'Reset your password';

  @override
  String get authResetDialogBody =>
      'We\'ll email you a reset code if this address has an account.';

  @override
  String get authSending => 'Sending…';

  @override
  String get authSendCode => 'Send code';

  @override
  String get authEnterCodeTitle => 'Enter your reset code';

  @override
  String get authEnterCodeBody => 'Check your inbox for the code we just sent.';

  @override
  String get authResetCodeLabel => 'Reset code';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authCodeRequired => 'Paste the code from the email';

  @override
  String get authSaving => 'Saving…';

  @override
  String get authSetNewPassword => 'Set new password';

  @override
  String get resetAppBarTitle => 'Reset password';

  @override
  String get resetSuccessTitle => 'Password updated';

  @override
  String get resetSuccessBody =>
      'Sign in with your new password. Any other sessions were signed out.';

  @override
  String get resetSignInButton => 'Sign in';

  @override
  String get resetChooseTitle => 'Choose a new password';

  @override
  String get resetNewPasswordLabel => 'New password';

  @override
  String get resetPasswordRequired => 'Password is required';

  @override
  String get resetPasswordTooShort => 'Password must be at least 8 characters';

  @override
  String get resetConfirmLabel => 'Confirm new password';

  @override
  String get resetConfirmRequired => 'Confirm your new password';

  @override
  String get resetPasswordsMismatch => 'Passwords don\'t match';

  @override
  String get resetSetNewPassword => 'Set new password';

  @override
  String get landingSignIn => 'Sign in';

  @override
  String get landingHeroTagline => 'Plan less. Travel more.';

  @override
  String get landingHeroSubtitle =>
      'Your AI travel companion — describe the trip you want and get a full day-by-day itinerary with routes, places, and flights.';

  @override
  String get landingHaveAccount => 'I already have an account';

  @override
  String get landingGetStarted => 'Get started';

  @override
  String get landingFeaturesTitle => 'Everything you need to plan the trip';

  @override
  String get landingFeatureAgentTitle => 'AI Travel Agent';

  @override
  String get landingFeatureAgentDescription =>
      'Describe your dream trip and get a complete itinerary in seconds.';

  @override
  String get landingPrivacyPolicy => 'Privacy Policy';

  @override
  String get landingTermsOfService => 'Terms of Service';

  @override
  String get landingCopyright => '© 2026 Golden Tempo LLC';

  @override
  String get verifyTitle => 'Verify email';

  @override
  String get verifySuccessTitle => 'Email verified ✓';

  @override
  String get verifySuccessBody =>
      'You\'re all set — thanks for confirming your address.';

  @override
  String get verifyLinkExpiredTitle => 'Link expired or already used';

  @override
  String get verifyLinkExpiredBody =>
      'Request a new verification email from your account.';

  @override
  String get verifyContinue => 'Continue';

  @override
  String get ssoTitle => 'Signing you in';

  @override
  String get ssoFailedTitle => 'Sign-in didn\'t complete';

  @override
  String get ssoErrorCancelled =>
      'Sign-in was cancelled or failed. Please try again.';

  @override
  String get ssoErrorExpired => 'This sign-in link expired. Please try again.';

  @override
  String get ssoBackToSignIn => 'Back to sign in';

  @override
  String get settingsTitle => 'Account settings';

  @override
  String get settingsProfileSection => 'Profile';

  @override
  String get settingsDisplayName => 'Display name';

  @override
  String get settingsSaveName => 'Save name';

  @override
  String get settingsNameUpdated => 'Name updated';

  @override
  String get settingsPasswordSection => 'Password';

  @override
  String get settingsCurrentPassword => 'Current password';

  @override
  String get settingsNewPassword => 'New password (8+ characters)';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsPasswordChanged =>
      'Password changed — other devices were signed out';

  @override
  String get settingsSessionsSection => 'Sessions';

  @override
  String get settingsSessionsHelp =>
      'Signs you out on every device, including this one.';

  @override
  String get settingsSignOutEverywhere => 'Sign out everywhere';

  @override
  String get settingsEmailPrefsSection => 'Email preferences';

  @override
  String get settingsTripReminders => 'Trip reminders';

  @override
  String get settingsTripRemindersSubtitle =>
      'Nudges about upcoming trips and things left to book.';

  @override
  String get settingsWeeklyIdeas => 'Weekly planning ideas';

  @override
  String get settingsWeeklyIdeasSubtitle =>
      'A weekly email with destination ideas and inspiration.';

  @override
  String get settingsLegalSection => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsTermsOfService => 'Terms of Service';

  @override
  String get settingsDangerZoneSection => 'Danger zone';

  @override
  String get settingsDeleteAccount => 'Delete account';

  @override
  String get settingsDeleteAccountTitle => 'Delete account?';

  @override
  String get settingsDeleteAccountBody =>
      'This permanently deletes your account, trips, preferences and alerts. There is no undo.';

  @override
  String get settingsConfirmPassword => 'Confirm your password';

  @override
  String get settingsDeleteForever => 'Delete forever';

  @override
  String get quizTitle => 'Set up your travel profile';

  @override
  String get quizSkip => 'Skip';

  @override
  String get quizFinish => 'Finish';

  @override
  String get quizStyleTitle => 'What\'s your travel style?';

  @override
  String get quizStyleSubtitle =>
      'Helps the planner match stays and activities to you.';

  @override
  String get quizInterestsTitle => 'What do you love doing on a trip?';

  @override
  String get quizInterestsSubtitle => 'Pick as many as you like.';

  @override
  String get quizCompanionsTitle => 'Who do you usually travel with?';

  @override
  String get quizCompanionSolo => 'solo';

  @override
  String get quizCompanionPartner => 'partner';

  @override
  String get quizCompanionFriends => 'friends';

  @override
  String get quizCompanionFamily => 'family with kids';

  @override
  String get quizCompanionVaries => 'it varies';

  @override
  String get quizHomeAirportTitle => 'Where do you fly from?';

  @override
  String get quizTripsTitle => 'Any trips you\'re dreaming about?';

  @override
  String get quizTripsSubtitle =>
      'Places, seasons, occasions — the planner will keep them in mind.';

  @override
  String get quizTripsHint =>
      'e.g. Japan for cherry blossom season, a Greek island hop next summer…';

  @override
  String get quizSaveFailed =>
      'Could not save your answers — try again, or skip for now.';

  @override
  String get quizProfileUpdated => 'Travel profile updated';
}
