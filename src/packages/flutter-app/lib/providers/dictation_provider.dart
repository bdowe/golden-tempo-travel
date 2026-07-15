import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/dictation_controller.dart';
import '../services/dictation_engine.dart';
import '../services/transcribe_api_service.dart';
import 'api_client_provider.dart';

/// Wraps the /transcribe endpoints (voice-dictation fallback path).
final transcribeApiServiceProvider = Provider<TranscribeApiService>((ref) {
  return TranscribeApiService(ref.watch(apiClientProvider));
});

/// Whether server-side transcription is configured, checked once per app
/// session so the mic can be hidden up front in browsers that also lack
/// built-in speech recognition.
final transcribeAvailabilityProvider = FutureProvider<bool>((ref) {
  return ref.watch(transcribeApiServiceProvider).availability();
});

/// Builds a per-composer [DictationController] bound to that composer's text
/// field. Widget tests override this to inject fake engines.
final dictationControllerFactoryProvider =
    Provider<DictationController Function(TextEditingController)>((ref) {
  return (textController) => DictationController(
        textController: textController,
        primary: SpeechToTextEngine(),
        fallback: RecorderEngine(ref.read(transcribeApiServiceProvider)),
        fallbackAvailable: () =>
            ref.read(transcribeAvailabilityProvider.future),
      );
});
