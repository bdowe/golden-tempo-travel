import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Localization entry points (specs/i18n-spanish).
///
/// [kSupportedLocales] is the single source of truth for which languages the
/// app ships: `MaterialApp.supportedLocales`, the locale provider's device
/// matching, and the settings picker all read it. Enabling a language is
/// therefore one line here plus its `.arb` file — and, just as importantly,
/// they can never disagree (a locale the provider resolved but MaterialApp
/// didn't support would send a language header for text the app can't render).
///
/// Spanish translations land ahead of enablement, so `es` stays out of this
/// list until the string extraction is complete.
const List<Locale> kSupportedLocales = [
  Locale('en'),
];

/// True when [languageCode] is a language this build can actually render.
bool isSupportedLanguage(String languageCode) =>
    kSupportedLocales.any((l) => l.languageCode == languageCode);

/// Shorthand for the generated lookups: `context.l10n.commonSave`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
