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
}
