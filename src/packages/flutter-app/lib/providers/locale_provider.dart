import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../services/account_api_service.dart';
import 'api_client_provider.dart';
import 'auth_provider.dart';

/// The app's language, and the single place it is decided (specs/i18n-spanish).
///
/// The client owns locale resolution: it picks the effective language once and
/// states it on every request via `Accept-Language`. The server never
/// re-derives it, which is what keeps an explicit override from disagreeing
/// with what the backend thinks the user reads.
///
/// Resolution order: explicit override, else the device language (when the app
/// ships translations for it), else English.

/// Storage key for the explicit choice. Device-wide rather than per-user: the
/// sign-in screen needs a language before anyone is signed in.
const String _overrideKey = 'locale_override';

/// Sentinel stored (and shown in the picker) for "follow the device".
const String kLocaleSystem = 'system';

@immutable
class LocaleState {
  /// The user's explicit choice: [kLocaleSystem], or a language code.
  final String override;

  /// The language actually in use, after resolving [override] against the
  /// device language and what this build supports. Never empty.
  final String effective;

  /// False until the stored override has been read; the app renders with the
  /// device-derived default in the meantime.
  final bool loaded;

  const LocaleState({
    this.override = kLocaleSystem,
    this.effective = 'en',
    this.loaded = false,
  });

  /// What to hand [MaterialApp.locale]: null when following the system, so
  /// Flutter does its own resolution against `supportedLocales`.
  Locale? get materialLocale =>
      override == kLocaleSystem ? null : Locale(effective);

  LocaleState copyWith({String? override, String? effective, bool? loaded}) =>
      LocaleState(
        override: override ?? this.override,
        effective: effective ?? this.effective,
        loaded: loaded ?? this.loaded,
      );
}

/// The device/browser language, folded to a supported language code, or null
/// when this build has no translations for it.
String? deviceLanguage() {
  for (final locale in PlatformDispatcher.instance.locales) {
    if (isSupportedLanguage(locale.languageCode)) return locale.languageCode;
  }
  return null;
}

/// Resolves an override against the device language and this build's
/// translations. Unsupported values (a stale override from a build that
/// shipped a language this one doesn't) fall back rather than sticking.
String resolveEffectiveLocale(String override) {
  if (override != kLocaleSystem && isSupportedLanguage(override)) {
    return override;
  }
  return deviceLanguage() ?? 'en';
}

class LocaleNotifier extends StateNotifier<LocaleState> {
  final Ref _ref;

  LocaleNotifier(this._ref) : super(const LocaleState()) {
    // Render immediately with the device-derived language; the stored override
    // arrives a frame or two later and only redraws if it differs.
    _apply(resolveEffectiveLocale(kLocaleSystem));
  }

  /// Reads the stored override. Called once at startup.
  Future<void> load() async {
    String override = kLocaleSystem;
    try {
      final prefs = await SharedPreferences.getInstance();
      override = prefs.getString(_overrideKey) ?? kLocaleSystem;
    } catch (_) {
      // Storage unavailable (private browsing, first run) — follow the device.
    }
    final effective = resolveEffectiveLocale(override);
    state = state.copyWith(
      override: override,
      effective: effective,
      loaded: true,
    );
    _apply(effective);
  }

  /// Records an explicit choice ([kLocaleSystem] to go back to following the
  /// device) and syncs it to the account.
  Future<void> setOverride(String override) async {
    final effective = resolveEffectiveLocale(override);
    state = state.copyWith(override: override, effective: effective);
    _apply(effective);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (override == kLocaleSystem) {
        await prefs.remove(_overrideKey);
      } else {
        await prefs.setString(_overrideKey, override);
      }
    } catch (_) {
      // The choice still applies for this session.
    }
    await syncToAccount();
  }

  /// Adopts the account's stored language on a device that has never made its
  /// own choice, so a second device follows the first. A local override always
  /// wins on the device where it was set — and if there is no local choice, the
  /// device's resolved language is pushed up instead, so the background email
  /// jobs (which have no request to negotiate from) always have a value.
  Future<void> reconcileWithAccount(String? accountLocale) async {
    if (state.override == kLocaleSystem &&
        accountLocale != null &&
        isSupportedLanguage(accountLocale) &&
        accountLocale != state.effective) {
      await setOverride(accountLocale);
      return;
    }
    if (accountLocale != state.effective) await syncToAccount();
  }

  /// Best-effort push of the effective language to the account. Never throws
  /// and never blocks the UI: a failed sync only costs a wrong-language email
  /// until the next successful one.
  Future<void> syncToAccount() async {
    if (!_ref.read(authProvider).isSignedIn) return;
    try {
      final api = _ref.read(apiClientProvider);
      final user = await AccountApiService(api).updateLocale(state.effective);
      _ref.read(authProvider.notifier).setUser(user);
    } catch (_) {
      // Offline or transient — retried on the next locale change or sign-in.
    }
  }

  /// Pushes [locale] into the two places that read it implicitly: the API
  /// client's `Accept-Language` header and intl's default for date/number
  /// formatting.
  void _apply(String locale) {
    _ref.read(apiClientProvider).localeTag = locale;
    Intl.defaultLocale = locale;
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, LocaleState>((ref) {
  return LocaleNotifier(ref)..load();
});
