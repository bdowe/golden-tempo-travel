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

  @override
  String get bookingCardEdit => 'Editar';

  @override
  String get bookingCardRemove => 'Quitar';

  @override
  String get bookingCardBooked => 'Reservado';

  @override
  String bookingCardOpenIn(String provider) {
    return 'Abrir en $provider';
  }

  @override
  String get bookingCardOpenSearch => 'Abrir búsqueda';

  @override
  String get calendarAddTo => 'Añadir al calendario';

  @override
  String get calendarGoogle => 'Google Calendar';

  @override
  String get calendarApple => 'Apple Calendar (.ics)';

  @override
  String calendarExportFailed(String error) {
    return 'No se pudo exportar el evento: $error';
  }

  @override
  String get bookingsTitle => 'Reservas';

  @override
  String get bookingsAddStay => 'Añadir alojamiento';

  @override
  String get bookingsAddTransport => 'Añadir transporte';

  @override
  String get bookingsAddBooking => 'Añadir reserva';

  @override
  String get bookingsEmptyMessage =>
      'Aún no has guardado nada — añade los alojamientos, el transporte y las demás reservas de tu viaje para tenerlo todo en un mismo sitio.';

  @override
  String get bookingsStays => 'Alojamientos';

  @override
  String get bookingsTransport => 'Transporte';

  @override
  String get bookingsOther => 'Otros';

  @override
  String get bookingsSuggested => 'Sugerido';

  @override
  String get bookingsKeep => 'Conservar';

  @override
  String get bookingsEdit => 'Editar';

  @override
  String get bookingsDismissSuggestion => 'Descartar sugerencia';

  @override
  String get bookingsOpenListing => 'Abrir anuncio';

  @override
  String get bookingsEditStay => 'Editar alojamiento';

  @override
  String get bookingsRemoveStay => 'Eliminar alojamiento';

  @override
  String get bookingsOpenBooking => 'Abrir reserva';

  @override
  String get bookingsEditTransport => 'Editar transporte';

  @override
  String get bookingsRemoveTransport => 'Eliminar transporte';

  @override
  String get bookingsAddAStay => 'Añadir un alojamiento';

  @override
  String get bookingsStayNameLabel => 'Nombre *';

  @override
  String get bookingsStayProviderLabel => 'Proveedor (Airbnb, Booking.com, …)';

  @override
  String get bookingsStayUrlLabel => 'URL del anuncio';

  @override
  String get bookingsStayAddressLabel => 'Dirección';

  @override
  String get bookingsCheckInOut => 'Entrada / salida';

  @override
  String get bookingsPriceNoteLabel => 'Nota de precio (p. ej. 120 €/noche)';

  @override
  String get bookingsSegmentFromLabel => 'Desde *';

  @override
  String get bookingsSegmentToLabel => 'Hasta *';

  @override
  String get bookingsDepartureDate => 'Fecha de salida';

  @override
  String get bookingsSegmentProviderLabel => 'Proveedor / compañía';

  @override
  String get bookingsSegmentUrlLabel => 'URL de la reserva';

  @override
  String get bookingsNotesLabel => 'Notas';

  @override
  String get bookingsModeFlight => 'vuelo';

  @override
  String get bookingsModeTrain => 'tren';

  @override
  String get bookingsModeBus => 'autobús';

  @override
  String get bookingsModeCar => 'coche';

  @override
  String get bookingsModeFerry => 'ferri';

  @override
  String get bookingsModeOther => 'otro';

  @override
  String get budgetTitle => 'Presupuesto';

  @override
  String get budgetEmptyTitle => 'Aún no hay presupuesto';

  @override
  String get budgetEmptyMessage =>
      'Fija un objetivo arriba o añade gastos abajo para controlar lo que gastas.';

  @override
  String budgetTargetSet(String amount, String currency) {
    return 'Objetivo: $amount ($currency)';
  }

  @override
  String get budgetNoTarget => 'Sin objetivo — solo se registra el gasto';

  @override
  String get budgetEditExpenseTitle => 'Editar gasto';

  @override
  String get budgetSetTargetTitle => 'Fijar objetivo de presupuesto';

  @override
  String get budgetCategoryLabel => 'Categoría';

  @override
  String get budgetLabelField => 'Etiqueta';

  @override
  String get budgetAmount => 'Importe';

  @override
  String get budgetCurrencyLabel => 'Moneda';

  @override
  String get budgetTargetLabel => 'Objetivo';

  @override
  String get budgetTargetHint => 'Déjalo en blanco para no fijar ninguno';

  @override
  String get budgetTargetHelp =>
      'Deja el objetivo en blanco para solo registrar tus gastos.';

  @override
  String get budgetExpenseOptions => 'Opciones del gasto';

  @override
  String get budgetMenuEdit => 'Editar';

  @override
  String get budgetTotalSpent => 'Total gastado';

  @override
  String get budgetRemaining => 'Restante';

  @override
  String get budgetAddHint => 'Añade un gasto…';

  @override
  String get budgetAddExpenseTooltip => 'Añadir gasto';

  @override
  String get budgetCategoryFlights => 'Vuelos';

  @override
  String get budgetCategoryLodging => 'Alojamiento';

  @override
  String get budgetCategoryFood => 'Comida';

  @override
  String get budgetCategoryActivities => 'Actividades';

  @override
  String get budgetCategoryTransport => 'Transporte';

  @override
  String get budgetCategoryShopping => 'Compras';

  @override
  String get budgetCategoryGeneral => 'General';

  @override
  String get checklistTitle => 'Equipaje y preparativos';

  @override
  String get checklistEmptyTitle => 'Aún no has preparado nada';

  @override
  String get checklistEmptyMessage =>
      'Añade elementos abajo o pídele al asistente de IA que te ayude a crear la lista.';

  @override
  String get checklistEditItemTitle => 'Editar elemento';

  @override
  String get checklistItemLabel => 'Elemento';

  @override
  String get checklistItemOptions => 'Opciones del elemento';

  @override
  String get checklistMenuEdit => 'Editar';

  @override
  String get checklistAddHint => 'Añade un elemento…';

  @override
  String get checklistAddItemTooltip => 'Añadir elemento';

  @override
  String get checklistCategoryDocuments => 'Documentos';

  @override
  String get checklistCategoryClothing => 'Ropa';

  @override
  String get checklistCategoryElectronics => 'Electrónica';

  @override
  String get checklistCategoryHealth => 'Salud';

  @override
  String get checklistCategoryGeneral => 'General';

  @override
  String get itemDialogTitle => 'Añadir lugar';

  @override
  String get itemDialogSearchLabel => 'Busca un lugar';

  @override
  String get itemDialogSearchHint => 'p. ej. Pastéis de Belém, Lisboa';

  @override
  String get itemDialogPickDifferent => 'Elegir otro lugar';

  @override
  String get itemDialogAddManually => '¿No lo encuentras? Añádelo manualmente';

  @override
  String get itemDialogPlaceNameLabel => 'Nombre del lugar';

  @override
  String get itemDialogSearchInstead => 'Mejor buscar lugares';

  @override
  String get itemDialogDayLabel => 'Día';

  @override
  String get itemDialogUnscheduled => 'Sin programar';

  @override
  String itemDialogDayN(int day) {
    return 'Día $day';
  }

  @override
  String itemDialogNewDay(int day) {
    return 'Nuevo día ($day)';
  }

  @override
  String get itemDialogTimeOfDayLabel => 'Momento del día';

  @override
  String get itemDialogTimeAny => 'Cualquiera';

  @override
  String get itemDialogTimeMorning => 'Mañana';

  @override
  String get itemDialogTimeAfternoon => 'Tarde';

  @override
  String get itemDialogTimeEvening => 'Noche';

  @override
  String get itemDialogCategoryAttraction => 'Atracción';

  @override
  String get itemDialogCategoryRestaurant => 'Restaurante';

  @override
  String get itemDialogAdd => 'Añadir';

  @override
  String get itemDialogNoResults =>
      'No se encontró ningún lugar — prueba con otra búsqueda o añade el lugar manualmente.';

  @override
  String get itemDialogSearchUnavailable =>
      'La búsqueda no está disponible — añade el lugar manualmente abajo.';

  @override
  String get itemDialogErrorEnterName => 'Escribe un nombre para el lugar.';

  @override
  String get itemDialogErrorPickPlace => 'Elige un lugar primero.';

  @override
  String itemDialogErrorAddFailed(String error) {
    return 'No se pudo añadir el lugar: $error';
  }

  @override
  String get commonOffline =>
      'Estás sin conexión — vuelve a conectarte para hacer cambios.';

  @override
  String get commonGenericError => 'Algo salió mal. Inténtalo de nuevo.';

  @override
  String get tripTitleFallback => 'Viaje';

  @override
  String get tripOtherPlaces => 'Otros lugares';

  @override
  String get tripOfflineGuard =>
      'Estás sin conexión — vuelve a conectarte para hacer cambios.';

  @override
  String get tripTravelModeDriving => 'En coche';

  @override
  String get tripTravelModeByTrain => 'En tren';

  @override
  String get tripTravelModeByBus => 'En autobús';

  @override
  String get tripTravelModeByFerry => 'En ferry';

  @override
  String get tripTravelModeMixed => 'Modos combinados';

  @override
  String get tripTravelModeFlying => 'En avión';

  @override
  String get tripTravelModeUnset => 'Modo de viaje';

  @override
  String get tripTravelModeTooltip => 'Modo de viaje';

  @override
  String get tripModeTrain => 'Tren';

  @override
  String get tripModeBus => 'Autobús';

  @override
  String get tripModeFerry => 'Ferry';

  @override
  String tripUpdateFailed(String error) {
    return 'Error al actualizar: $error';
  }

  @override
  String tripDeleteFailed(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String tripReorderFailed(String error) {
    return 'No se pudo reordenar: $error';
  }

  @override
  String tripLeaveFailed(String error) {
    return 'No se pudo quitar el viaje: $error';
  }

  @override
  String tripAddStayFailed(String error) {
    return 'No se pudo añadir el alojamiento: $error';
  }

  @override
  String tripRemoveStayFailed(String error) {
    return 'No se pudo quitar el alojamiento: $error';
  }

  @override
  String tripUpdateStayFailed(String error) {
    return 'No se pudo actualizar el alojamiento: $error';
  }

  @override
  String tripKeepStayFailed(String error) {
    return 'No se pudo conservar el alojamiento: $error';
  }

  @override
  String tripAddTransportFailed(String error) {
    return 'No se pudo añadir el transporte: $error';
  }

  @override
  String tripRemoveTransportFailed(String error) {
    return 'No se pudo quitar el transporte: $error';
  }

  @override
  String tripUpdateTransportFailed(String error) {
    return 'No se pudo actualizar el transporte: $error';
  }

  @override
  String tripKeepTransportFailed(String error) {
    return 'No se pudo conservar el transporte: $error';
  }

  @override
  String tripShareLinkFailed(String error) {
    return 'No se pudo crear el enlace para compartir: $error';
  }

  @override
  String tripPrintExportFailed(String error) {
    return 'No se pudo abrir la vista para imprimir: $error';
  }

  @override
  String tripCalendarExportFailed(String error) {
    return 'No se pudo exportar el calendario: $error';
  }

  @override
  String tripEventExportFailed(String error) {
    return 'No se pudo exportar el evento: $error';
  }

  @override
  String tripSharingOffFailed(String error) {
    return 'No se pudo desactivar el uso compartido: $error';
  }

  @override
  String tripInviteFailed(String error) {
    return 'No se pudo crear la invitación: $error';
  }

  @override
  String tripRemoveItemFailed(String name, String error) {
    return 'No se pudo quitar $name: $error';
  }

  @override
  String tripRestoreItemFailed(String name, String error) {
    return 'No se pudo restaurar $name: $error';
  }

  @override
  String tripUpdateItemFailed(String name, String error) {
    return 'No se pudo actualizar $name: $error';
  }

  @override
  String tripMoveItemFailed(String error) {
    return 'No se pudo mover el elemento: $error';
  }

  @override
  String tripUpdateBookingFailed(String error) {
    return 'No se pudo actualizar la reserva: $error';
  }

  @override
  String tripUndoFailed(String error) {
    return 'No se pudo deshacer: $error';
  }

  @override
  String tripAddPackingFailed(String error) {
    return 'No se pudo añadir el artículo de equipaje: $error';
  }

  @override
  String tripLoadBudgetFailed(String error) {
    return 'No se pudo cargar el presupuesto: $error';
  }

  @override
  String tripUpdateBudgetFailed(String error) {
    return 'No se pudo actualizar el presupuesto: $error';
  }

  @override
  String tripSaveFailed(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get tripOpenLinkFailed => 'No se pudo abrir el enlace';

  @override
  String get tripFerrySearchFailed => 'No se pudo abrir la búsqueda de ferris';

  @override
  String get tripLoadFailed => 'No se pudo cargar este viaje';

  @override
  String get tripEditTitle => 'Editar título';

  @override
  String get tripDeleteTitle => '¿Eliminar el viaje?';

  @override
  String get tripDeleteBody => 'Esta acción no se puede deshacer.';

  @override
  String get tripLeaveTitle => '¿Quitar de mis viajes?';

  @override
  String get tripLeaveBody =>
      'Perderás el acceso hasta que vuelvan a invitarte. El viaje en sí no se elimina.';

  @override
  String get tripRemove => 'Quitar';

  @override
  String get tripUndo => 'Deshacer';

  @override
  String get tripAddPlacesBeforeRefine =>
      'Añade algunos lugares antes de refinar con IA.';

  @override
  String get tripAssistantLabel => 'Asistente de viaje';

  @override
  String tripRefiningSection(String section) {
    return 'Refinando $section';
  }

  @override
  String tripRefineCity(String city) {
    return 'Refinar $city';
  }

  @override
  String get tripRefineThisDay => 'Refinar este día';

  @override
  String get tripRefineWithAI => 'Refinar con IA';

  @override
  String get tripAskAI => 'Pregunta a la IA sobre este viaje';

  @override
  String get tripShareLinkCopied =>
      'Enlace para compartir copiado al portapapeles';

  @override
  String get tripSharingTurnedOff =>
      'Uso compartido desactivado — los enlaces ya no funcionan (los coplanificadores y seguidores actuales conservan el acceso)';

  @override
  String tripCoPlanInviteMessage(String summary) {
    return 'Planifica conmigo: $summary';
  }

  @override
  String get tripInviteCopied =>
      'Invitación de coplanificador copiada — cualquiera que la tenga puede editar';

  @override
  String get tripCoPlannerRemoved => 'Coplanificador eliminado';

  @override
  String tripInviteSent(String email) {
    return 'Invitación enviada a $email';
  }

  @override
  String get tripShareTrip => 'Compartir viaje';

  @override
  String get tripShareLinkAction => 'Compartir enlace…';

  @override
  String get tripCopyShareLink => 'Copiar enlace para compartir';

  @override
  String get tripShareInviteAction => 'Compartir invitación de coplanificador…';

  @override
  String get tripCopyInviteLink => 'Copiar enlace de invitación (puede editar)';

  @override
  String get tripManageAccess => 'Gestionar acceso';

  @override
  String get tripPrintSavePdf => 'Imprimir / Guardar como PDF';

  @override
  String get tripAddToCalendar => 'Añadir al calendario';

  @override
  String get tripTurnOffSharing => 'Desactivar el uso compartido';

  @override
  String get tripDeleteTrip => 'Eliminar viaje';

  @override
  String get tripRemoveFromMyTrips => 'Quitar de mis viajes';

  @override
  String get tripLocalIntel => 'Información local';

  @override
  String tripLocalGuideTitle(String title) {
    return 'Guía local: $title';
  }

  @override
  String tripGuideBy(String name) {
    return 'Por $name';
  }

  @override
  String get tripEventsWhileHere => 'Eventos mientras estás aquí';

  @override
  String tripFindingEvents(String city) {
    return 'Buscando eventos en $city…';
  }

  @override
  String tripFindEventsIn(String city) {
    return 'Buscar eventos en $city';
  }

  @override
  String tripRecommendedBy(String name) {
    return 'Recomendado por $name';
  }

  @override
  String get tripFindFlights => 'Buscar vuelos';

  @override
  String get tripFindFerries => 'Buscar ferris';

  @override
  String get tripAddBooking => 'Añadir una reserva';

  @override
  String get tripEditBooking => 'Editar reserva';

  @override
  String get tripFieldType => 'Tipo';

  @override
  String get tripKindStay => 'Alojamiento';

  @override
  String get tripKindTransport => 'Transporte';

  @override
  String get tripKindOther => 'Otro';

  @override
  String get tripFieldTitle => 'Título';

  @override
  String get tripFieldOrigin => 'Origen (opcional)';

  @override
  String get tripFieldDestination => 'Destino (opcional)';

  @override
  String get tripFieldDepartDate => 'Fecha de salida (opcional)';

  @override
  String get tripFieldCheckIn => 'Entrada (opcional)';

  @override
  String get tripFieldCheckOut => 'Salida (opcional)';

  @override
  String get tripFieldLink => 'Enlace (opcional, sustituye a la búsqueda)';

  @override
  String get tripTitleRequired => 'El título es obligatorio';

  @override
  String get tripClearDate => 'Borrar fecha';

  @override
  String get tripItinerary => 'Itinerario';

  @override
  String get tripToday => 'Hoy';

  @override
  String get tripAddPlace => 'Añadir lugar';

  @override
  String get tripFilterAll => 'Todos';

  @override
  String get tripFilterAttractions => 'Atracciones';

  @override
  String get tripFilterRestaurants => 'Restaurantes';

  @override
  String get tripFilterNoMatch => 'Ningún lugar coincide con este filtro.';

  @override
  String get tripNoPlacesYet => 'Aún no hay lugares';

  @override
  String get tripNoPlacesYetMessage =>
      'Refina con IA o añade un lugar para empezar tu itinerario.';

  @override
  String get tripNoMappedPlaces => 'No hay lugares en el mapa';

  @override
  String tripNoPlacesOnDay(int day) {
    return 'No hay lugares marcados el día $day';
  }

  @override
  String get tripAddPlaceMapHint => 'Añade un lugar para verlo en el mapa.';

  @override
  String tripDayN(int n) {
    return 'Día $n';
  }

  @override
  String tripDayTripTo(String town) {
    return 'Excursión · $town';
  }

  @override
  String get tripDayTripFallback => 'Excursión';

  @override
  String tripTonight(String stays) {
    return 'Esta noche: $stays';
  }

  @override
  String tripTravelMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String tripTravelHours(int hours) {
    return '$hours h';
  }

  @override
  String tripTravelHoursMinutes(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String tripTravelFromHub(String duration, String hub) {
    return '$duration desde $hub';
  }

  @override
  String tripTravelTotal(String duration) {
    return '$duration de trayecto';
  }

  @override
  String tripRainChance(int percent) {
    return '$percent% de lluvia';
  }

  @override
  String get tripTypicalForDates => 'lo habitual en estas fechas';

  @override
  String get tripPlaceActions => 'Acciones del lugar';

  @override
  String get tripOpenInGoogleMaps => 'Abrir en Google Maps';

  @override
  String get tripEdit => 'Editar';

  @override
  String get tripMoveUp => 'Subir';

  @override
  String get tripMoveDown => 'Bajar';

  @override
  String get tripReorderSection => 'Reordenar sección';

  @override
  String get tripAddToGoogleCalendar => 'Añadir a Google Calendar';

  @override
  String get tripAddToAppleCalendar => 'Añadir a Apple Calendar (.ics)';

  @override
  String tripRemovedItem(String name) {
    return '$name eliminado';
  }

  @override
  String tripMovedToDay(int day) {
    return 'Movido al día $day';
  }

  @override
  String get tripMarkedAsBooked => 'Marcado como reservado';

  @override
  String tripAddedToPacking(String item) {
    return '\"$item\" añadido al equipaje';
  }

  @override
  String get tripSetBudgetTarget => 'Definir objetivo de presupuesto';

  @override
  String tripBudgetTargetLabel(String currency) {
    return 'Objetivo ($currency)';
  }

  @override
  String get tripBudgetTargetHint =>
      'Déjalo en blanco para solo registrar los gastos';

  @override
  String get tripRename => 'Cambiar nombre';

  @override
  String get tripAddDates => 'Añadir fechas';

  @override
  String get tripChangeStatus => 'Cambiar estado';

  @override
  String get tripStatusDraft => 'Borrador';

  @override
  String get tripStatusPlanned => 'Planificado';

  @override
  String tripCoPlanningWith(String name) {
    return 'Planificando con $name — tus cambios se guardan para todos.';
  }

  @override
  String get tripCoPlanningShared =>
      'Planificando un viaje compartido — tus cambios se guardan para todos.';

  @override
  String tripSharedBy(String name) {
    return 'Compartido por $name — solo lectura.';
  }

  @override
  String get tripSharedViewOnly => 'Viaje compartido — solo lectura.';

  @override
  String tripUpdatedBy(String name, String time) {
    return 'Actualizado por $name · $time';
  }

  @override
  String get tripOverview => 'Resumen';

  @override
  String get tripShowMore => 'Mostrar más';

  @override
  String get tripShowLess => 'Mostrar menos';

  @override
  String get tripTimeRecently => 'hace poco';

  @override
  String get tripTimeJustNow => 'ahora mismo';

  @override
  String tripTimeMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String tripTimeHoursAgo(int hours) {
    return 'hace $hours h';
  }

  @override
  String tripTimeDaysAgo(int days) {
    return 'hace $days d';
  }

  @override
  String get tripFriendEmail => 'Correo de tu amigo';

  @override
  String get tripInvite => 'Invitar';

  @override
  String get tripNoCoPlanners =>
      'Aún no hay coplanificadores. Invita a un amigo por correo arriba o copia un enlace de invitación desde el menú de compartir.';

  @override
  String get tripRoleViewer => 'Lector';

  @override
  String get tripRoleCanEdit => 'Puede editar';

  @override
  String get tripRemoveAccess => 'Quitar acceso';

  @override
  String get tripPendingInvites => 'Invitaciones pendientes';

  @override
  String tripInvited(String expires) {
    return 'Invitado — $expires';
  }

  @override
  String get tripRevokeInvite => 'Revocar invitación';

  @override
  String tripExpiresInDays(int days) {
    return 'caduca en $days d';
  }

  @override
  String tripExpiresInHours(int hours) {
    return 'caduca en $hours h';
  }

  @override
  String get tripExpiresSoon => 'caduca pronto';

  @override
  String get tripEditPlace => 'Editar lugar';

  @override
  String get tripFieldName => 'Nombre';

  @override
  String get tripFieldCity => 'Ciudad';

  @override
  String get tripFieldDay => 'Día';

  @override
  String get tripCategoryAttraction => 'Atracción';

  @override
  String get tripCategoryRestaurant => 'Restaurante';

  @override
  String get tripTimeMorning => 'Mañana';

  @override
  String get tripTimeAfternoon => 'Tarde';

  @override
  String get tripTimeEvening => 'Noche';

  @override
  String get tripReorderPlaces => 'Reordenar lugares';

  @override
  String get tripReorderHint =>
      'Arrastra para cambiar el orden de visita dentro de esta sección.';

  @override
  String get tripSaveOrder => 'Guardar orden';

  @override
  String get tripsListTitle => 'Mis viajes';

  @override
  String get tripsListErrorTitle => 'No se pudieron cargar los viajes';

  @override
  String get tripsListErrorMessage =>
      'Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get tripsListEmptyTitle => 'Aún no tienes viajes';

  @override
  String get tripsListEmptyMessage =>
      'Habla con el agente de IA para crear tu primer viaje.';

  @override
  String get tripsListPlanTrip => 'Planear un viaje';

  @override
  String get tripsListSharedWithYou => 'Compartidos contigo';

  @override
  String tripsListCreated(String date) {
    return 'Creado el $date';
  }

  @override
  String tripsListPlannedWith(String name) {
    return 'Planeado con $name';
  }

  @override
  String tripsListSharedBy(String name) {
    return 'Compartido por $name';
  }

  @override
  String get tripsListVersionsError => 'No se pudieron cargar las versiones';

  @override
  String tripsListVersionLatest(String date) {
    return 'más reciente · $date';
  }

  @override
  String tripsListVersionNumbered(int version, String date) {
    return 'v$version · $date';
  }

  @override
  String get homeGreetingMorning => 'Buenos días';

  @override
  String get homeGreetingAfternoon => 'Buenas tardes';

  @override
  String get homeGreetingEvening => 'Buenas noches';

  @override
  String homeGreetingNamed(String greeting, String name) {
    return '$greeting, $name';
  }

  @override
  String get homeGreetingSubtitle => '¿Adónde vamos ahora?';

  @override
  String get homeHeroTitle => 'Planea menos. Viaja más.';

  @override
  String get homeHeroSubtitle =>
      'Cuéntame el viaje que sueñas y armaré el itinerario completo — lugares, días y rutas.';

  @override
  String get homeHeroCta => 'Vamos';

  @override
  String get homeSuggestionParis => '2 días en París';

  @override
  String get homeSuggestionRome => 'Museos en Roma';

  @override
  String get homeSuggestionTokyo => 'Fin de semana en Tokio';

  @override
  String get homeStatusDraft => 'Borrador';

  @override
  String get homeStatusPlanned => 'Planeado';

  @override
  String get homeRecentTripEyebrow => 'CONTINÚA DONDE LO DEJASTE';

  @override
  String get homeLocalGuidesTitle => 'Guías locales';

  @override
  String homeGuideByline(String name) {
    return 'Por $name';
  }

  @override
  String get shellNavHome => 'Inicio';

  @override
  String get shellNavPlan => 'Planear';

  @override
  String get shellNavTrips => 'Viajes';

  @override
  String get healthMetricsErrorTitle => 'No se pudieron cargar las métricas';

  @override
  String get healthHealthErrorTitle => 'No se pudo cargar el estado';

  @override
  String get healthProcessSection => 'Proceso';

  @override
  String get healthRoutesSection => 'Rutas';

  @override
  String get healthUptime => 'Tiempo activo';

  @override
  String get healthRequests => 'Solicitudes';

  @override
  String get healthErrorRate => 'Tasa de errores';

  @override
  String get healthGoroutines => 'Goroutines';

  @override
  String get healthMemory => 'Memoria';

  @override
  String get healthPlacesCalls => 'Llamadas a Places';

  @override
  String healthCacheHits(int count) {
    return '$count aciertos de caché';
  }

  @override
  String get healthColRoute => 'Ruta';

  @override
  String get healthColMethod => 'Método';

  @override
  String get healthColCount => 'Cantidad';

  @override
  String get healthColErrorPct => '% de errores';

  @override
  String get healthDependenciesSection => 'Dependencias';

  @override
  String get healthDatabase => 'Base de datos';

  @override
  String healthPing(int ms) {
    return 'ping de $ms ms';
  }

  @override
  String get healthPillOk => 'ok';

  @override
  String get healthPillUnreachable => 'inaccesible';

  @override
  String get healthPillConfigured => 'configurado';

  @override
  String get healthPillNotConfigured => 'sin configurar';

  @override
  String get healthPillUnknown => 'desconocido';

  @override
  String get healthPillStale => 'desactualizada';

  @override
  String get healthPillFresh => 'reciente';

  @override
  String get healthBackupsSection => 'Copias de seguridad';

  @override
  String get healthLastBackup => 'Última copia de seguridad';

  @override
  String healthBackupAge(String age) {
    return 'hace $age';
  }

  @override
  String get healthNoBackupRecorded => 'sin copias registradas';

  @override
  String get healthBuildSection => 'Compilación';

  @override
  String healthRelease(String release) {
    return 'versión $release';
  }

  @override
  String get healthDegradedTitle => 'Sistema degradado';

  @override
  String get reviewSectionTitle => 'Estado del viaje';

  @override
  String reviewCountToReview(int count) {
    return '$count por revisar';
  }

  @override
  String get reviewEmptyTitle => 'Todo en orden';

  @override
  String get reviewEmptyMessage =>
      'No encontramos problemas — tu viaje va bien.';

  @override
  String get reviewSeverityCritical => 'Crítico';

  @override
  String get reviewSeverityWarning => 'Advertencia';

  @override
  String get reviewSeverityInfo => 'Información';

  @override
  String get reviewOfflineSnack =>
      'Estás sin conexión — vuelve a conectarte para hacer más comprobaciones.';

  @override
  String get reviewHoursChecked => 'Horarios comprobados';

  @override
  String get reviewCheckHours => 'Comprobar también los horarios';

  @override
  String get liveTripEyebrow => 'SUCEDIENDO AHORA';

  @override
  String get liveTripStatusLive => 'En curso';

  @override
  String liveTripDay(int day) {
    return 'Día $day';
  }

  @override
  String liveTripDayOfTotal(int day, int total) {
    return 'Día $day de $total';
  }

  @override
  String get continueChatsTitle => 'Continúa donde lo dejaste';

  @override
  String get continueChatsReopenError => 'No se pudo reabrir esa conversación.';

  @override
  String get continueChatsDismissError =>
      'No se pudo descartar esa conversación.';

  @override
  String get continueChatsDismiss => 'Descartar';

  @override
  String get mapNoMappedPlaces => 'No hay lugares en el mapa';

  @override
  String get mapZoomIn => 'Acercar';

  @override
  String get mapZoomOut => 'Alejar';

  @override
  String get mapResetMap => 'Restablecer mapa';

  @override
  String get accountMenuTooltip => 'Cuenta';

  @override
  String get accountMenuTravelProfile => 'Perfil de viaje';

  @override
  String get accountMenuPriceAlerts => 'Alertas de precio';

  @override
  String get accountMenuRetakeQuiz => 'Repetir el cuestionario de viaje';

  @override
  String get accountMenuAccountSettings => 'Ajustes de la cuenta';

  @override
  String get accountMenuLocalIntelAdmin => 'Administración de info local';

  @override
  String get accountMenuMetrics => 'Métricas';

  @override
  String get accountMenuSignOut => 'Cerrar sesión';
}
