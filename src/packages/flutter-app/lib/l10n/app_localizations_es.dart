// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Golden Tempo Travel';

  @override
  String get languageSectionTitle => 'Idioma';

  @override
  String get languageSystemDefault => 'Predeterminado del sistema';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageChangeNote =>
      'Los viajes y las notas que ya guardaste se mantienen en el idioma en que se escribieron.';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonNext => 'Siguiente';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonSeeAll => 'Ver todo';

  @override
  String citiesTwo(String first, String second) {
    return '$first y $second';
  }

  @override
  String citiesMore(String first, String second, int count) {
    return '$first y $second +$count más';
  }

  @override
  String get prefsTitle => 'Perfil de viaje';

  @override
  String get prefsBudget => 'Presupuesto';

  @override
  String get prefsPace => 'Ritmo';

  @override
  String get prefsInterests => 'Intereses';

  @override
  String get prefsAddInterest => 'Añadir un interés';

  @override
  String get prefsHomeAirport => 'Aeropuerto de origen';

  @override
  String get prefsHomeAirportHelp =>
      'Se usa como origen predeterminado al planificar vuelos.';

  @override
  String get prefsProfileNotes => 'Notas del perfil';

  @override
  String get prefsProfileNotesHelp =>
      'Tu agente de IA mantiene estas notas a medida que te conoce. Puedes editarlas o borrarlas cuando quieras.';

  @override
  String get prefsProfileNotesHint =>
      'Todavía no hay notas: el agente las va añadiendo mientras planificas viajes.';

  @override
  String get prefsSaved => 'Preferencias guardadas';

  @override
  String get prefsSaveFailed => 'No se pudieron guardar las preferencias';

  @override
  String get prefsBudgetLow => 'económico';

  @override
  String get prefsBudgetMid => 'medio';

  @override
  String get prefsBudgetLuxury => 'lujo';

  @override
  String get prefsPaceRelaxed => 'relajado';

  @override
  String get prefsPaceBalanced => 'equilibrado';

  @override
  String get prefsPacePacked => 'intenso';

  @override
  String get prefsInterestMuseums => 'museos';

  @override
  String get prefsInterestFood => 'gastronomía';

  @override
  String get prefsInterestNightlife => 'vida nocturna';

  @override
  String get prefsInterestNature => 'naturaleza';

  @override
  String get prefsInterestHistory => 'historia';

  @override
  String get prefsInterestArt => 'arte';

  @override
  String get prefsInterestShopping => 'compras';

  @override
  String get prefsInterestOutdoors => 'aire libre';

  @override
  String get prefsInterestBeaches => 'playas';

  @override
  String get prefsInterestArchitecture => 'arquitectura';

  @override
  String get ssoContinueWithGoogle => 'Continuar con Google';

  @override
  String get ssoContinueWithApple => 'Continuar con Apple';

  @override
  String get ssoDividerOr => 'o';

  @override
  String get authWelcomeBack => 'Bienvenido de nuevo';

  @override
  String get authCreateAccountTitle => 'Crea tu cuenta';

  @override
  String get authEmailLabel => 'Correo electrónico';

  @override
  String get authEmailRequired => 'El correo electrónico es obligatorio';

  @override
  String get authEmailInvalid => 'Introduce un correo electrónico válido';

  @override
  String get authPasswordLabel => 'Contraseña';

  @override
  String get authPasswordRequired => 'La contraseña es obligatoria';

  @override
  String get authPasswordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

  @override
  String get authDisplayNameLabel => 'Nombre visible (opcional)';

  @override
  String get authSignIn => 'Iniciar sesión';

  @override
  String get authCreateAccount => 'Crear cuenta';

  @override
  String get authNoAccountPrompt => '¿No tienes cuenta? Regístrate';

  @override
  String get authHaveAccountPrompt => '¿Ya tienes cuenta? Inicia sesión';

  @override
  String get authForgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get authPasswordUpdatedSnack =>
      'Contraseña actualizada — inicia sesión con tu nueva contraseña';

  @override
  String get authResetDialogTitle => 'Restablece tu contraseña';

  @override
  String get authResetDialogBody =>
      'Te enviaremos por correo un código de restablecimiento si esta dirección tiene una cuenta.';

  @override
  String get authSending => 'Enviando…';

  @override
  String get authSendCode => 'Enviar código';

  @override
  String get authEnterCodeTitle => 'Introduce tu código de restablecimiento';

  @override
  String get authEnterCodeBody =>
      'Revisa tu bandeja de entrada para ver el código que acabamos de enviarte.';

  @override
  String get authResetCodeLabel => 'Código de restablecimiento';

  @override
  String get authNewPasswordLabel => 'Nueva contraseña';

  @override
  String get authCodeRequired => 'Pega el código del correo';

  @override
  String get authSaving => 'Guardando…';

  @override
  String get authSetNewPassword => 'Guardar nueva contraseña';

  @override
  String get resetAppBarTitle => 'Restablecer contraseña';

  @override
  String get resetSuccessTitle => 'Contraseña actualizada';

  @override
  String get resetSuccessBody =>
      'Inicia sesión con tu nueva contraseña. Se cerraron las demás sesiones.';

  @override
  String get resetSignInButton => 'Iniciar sesión';

  @override
  String get resetChooseTitle => 'Elige una nueva contraseña';

  @override
  String get resetNewPasswordLabel => 'Nueva contraseña';

  @override
  String get resetPasswordRequired => 'La contraseña es obligatoria';

  @override
  String get resetPasswordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

  @override
  String get resetConfirmLabel => 'Confirma la nueva contraseña';

  @override
  String get resetConfirmRequired => 'Confirma tu nueva contraseña';

  @override
  String get resetPasswordsMismatch => 'Las contraseñas no coinciden';

  @override
  String get resetSetNewPassword => 'Guardar nueva contraseña';

  @override
  String get landingSignIn => 'Iniciar sesión';

  @override
  String get landingHeroTagline => 'Planifica menos. Viaja más.';

  @override
  String get landingHeroSubtitle =>
      'Tu compañero de viaje con IA: describe el viaje que quieres y recibe un itinerario completo, día a día, con rutas, lugares y vuelos.';

  @override
  String get landingHaveAccount => 'Ya tengo una cuenta';

  @override
  String get landingGetStarted => 'Empezar';

  @override
  String get landingFeaturesTitle =>
      'Todo lo que necesitas para planificar el viaje';

  @override
  String get landingFeatureAgentTitle => 'Agente de viajes con IA';

  @override
  String get landingFeatureAgentDescription =>
      'Describe el viaje de tus sueños y recibe un itinerario completo en segundos.';

  @override
  String get landingPrivacyPolicy => 'Política de privacidad';

  @override
  String get landingTermsOfService => 'Términos del servicio';

  @override
  String get landingCopyright => '© 2026 Golden Tempo LLC';

  @override
  String get verifyTitle => 'Verificar correo';

  @override
  String get verifySuccessTitle => 'Correo verificado ✓';

  @override
  String get verifySuccessBody =>
      'Todo listo: gracias por confirmar tu dirección.';

  @override
  String get verifyLinkExpiredTitle => 'El enlace caducó o ya se usó';

  @override
  String get verifyLinkExpiredBody =>
      'Solicita un nuevo correo de verificación desde tu cuenta.';

  @override
  String get verifyContinue => 'Continuar';

  @override
  String get ssoTitle => 'Iniciando tu sesión';

  @override
  String get ssoFailedTitle => 'No se completó el inicio de sesión';

  @override
  String get ssoErrorCancelled =>
      'El inicio de sesión se canceló o falló. Inténtalo de nuevo.';

  @override
  String get ssoErrorExpired =>
      'Este enlace de inicio de sesión caducó. Inténtalo de nuevo.';

  @override
  String get ssoBackToSignIn => 'Volver a iniciar sesión';

  @override
  String get settingsTitle => 'Ajustes de la cuenta';

  @override
  String get settingsProfileSection => 'Perfil';

  @override
  String get settingsDisplayName => 'Nombre visible';

  @override
  String get settingsSaveName => 'Guardar nombre';

  @override
  String get settingsNameUpdated => 'Nombre actualizado';

  @override
  String get settingsPasswordSection => 'Contraseña';

  @override
  String get settingsCurrentPassword => 'Contraseña actual';

  @override
  String get settingsNewPassword => 'Contraseña nueva (8 caracteres o más)';

  @override
  String get settingsChangePassword => 'Cambiar contraseña';

  @override
  String get settingsPasswordChanged =>
      'Contraseña cambiada: se cerró la sesión en los demás dispositivos';

  @override
  String get settingsSessionsSection => 'Sesiones';

  @override
  String get settingsSessionsHelp =>
      'Cierra tu sesión en todos los dispositivos, incluido este.';

  @override
  String get settingsSignOutEverywhere =>
      'Cerrar sesión en todos los dispositivos';

  @override
  String get settingsEmailPrefsSection => 'Preferencias de correo';

  @override
  String get settingsTripReminders => 'Recordatorios de viaje';

  @override
  String get settingsTripRemindersSubtitle =>
      'Avisos sobre viajes próximos y cosas que te faltan por reservar.';

  @override
  String get settingsWeeklyIdeas => 'Ideas semanales para planificar';

  @override
  String get settingsWeeklyIdeasSubtitle =>
      'Un correo semanal con ideas de destinos e inspiración.';

  @override
  String get settingsLegalSection => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Política de privacidad';

  @override
  String get settingsTermsOfService => 'Términos del servicio';

  @override
  String get settingsDangerZoneSection => 'Zona de peligro';

  @override
  String get settingsDeleteAccount => 'Eliminar cuenta';

  @override
  String get settingsDeleteAccountTitle => '¿Eliminar tu cuenta?';

  @override
  String get settingsDeleteAccountBody =>
      'Esto elimina de forma permanente tu cuenta, tus viajes, tus preferencias y tus alertas. No se puede deshacer.';

  @override
  String get settingsConfirmPassword => 'Confirma tu contraseña';

  @override
  String get settingsDeleteForever => 'Eliminar para siempre';

  @override
  String get quizTitle => 'Configura tu perfil de viaje';

  @override
  String get quizSkip => 'Omitir';

  @override
  String get quizFinish => 'Finalizar';

  @override
  String get quizStyleTitle => '¿Cuál es tu estilo de viaje?';

  @override
  String get quizStyleSubtitle =>
      'Ayuda al planificador a ajustar los alojamientos y las actividades a ti.';

  @override
  String get quizInterestsTitle => '¿Qué te encanta hacer en un viaje?';

  @override
  String get quizInterestsSubtitle => 'Elige todas las que quieras.';

  @override
  String get quizCompanionsTitle => '¿Con quién sueles viajar?';

  @override
  String get quizCompanionSolo => 'en solitario';

  @override
  String get quizCompanionPartner => 'en pareja';

  @override
  String get quizCompanionFriends => 'con amigos';

  @override
  String get quizCompanionFamily => 'en familia con niños';

  @override
  String get quizCompanionVaries => 'depende';

  @override
  String get quizHomeAirportTitle => '¿Desde dónde vuelas?';

  @override
  String get quizTripsTitle => '¿Sueñas con algún viaje?';

  @override
  String get quizTripsSubtitle =>
      'Lugares, épocas del año, ocasiones: el planificador los tendrá en cuenta.';

  @override
  String get quizTripsHint =>
      'p. ej. Japón en temporada de cerezos en flor, saltar de isla en isla por Grecia el próximo verano…';

  @override
  String get quizSaveFailed =>
      'No se pudieron guardar tus respuestas: inténtalo de nuevo u omítelo por ahora.';

  @override
  String get quizProfileUpdated => 'Perfil de viaje actualizado';
}
