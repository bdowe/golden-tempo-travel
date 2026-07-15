import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'transcribe_api_service.dart';

/// One dictation session's worth of events. The stream a [DictationEngine]
/// returns closes when the session ends (event style matches [PlanEvent]).
class DictationEvent {
  /// `partial` | `final` | `transcribing` | `error`
  final String type;

  /// Transcript text for partial/final events.
  final String text;

  /// Machine error code for error events:
  /// `permission` | `engine-failed` | `unavailable` | `failed`.
  final String errorCode;

  const DictationEvent(this.type, {this.text = '', this.errorCode = ''});
}

/// One speech-capture backend. Sessions are one-shot: [start] returns a fresh
/// event stream; [stop] ends the session gracefully (final results still
/// arrive), [cancel] discards it. Only one session runs at a time per app —
/// there is only one microphone.
abstract class DictationEngine {
  /// Feature-detects the backend. False means this engine can never run in
  /// the current environment (e.g. no Web Speech API in this browser).
  Future<bool> initialize();

  Stream<DictationEvent> start();

  Future<void> stop();

  Future<void> cancel();
}

/// Session caps shared by both engines: dictation is for a spoken chat
/// message, not long-form recording.
const dictationMaxDuration = Duration(seconds: 60);
const dictationPauseFor = Duration(seconds: 3);

/// Live path: the `speech_to_text` plugin (Web Speech API on web, native
/// recognizers on iOS/Android). Emits partial transcripts as the user speaks.
///
/// The plugin registers its platform callbacks per [stt.SpeechToText]
/// instance at initialize time, and a second instance's initialize would
/// steal them — with two live composers (agent tab + trip refine panel) that
/// would silently drop the other composer's results. So all engine instances
/// share one plugin object and route events to whichever engine owns the
/// active session.
class SpeechToTextEngine implements DictationEngine {
  static final stt.SpeechToText _sharedSpeech = stt.SpeechToText();
  static SpeechToTextEngine? _active;

  final stt.SpeechToText _speech;
  StreamController<DictationEvent>? _events;

  SpeechToTextEngine({stt.SpeechToText? speech})
      : _speech = speech ?? _sharedSpeech;

  @override
  Future<bool> initialize() async {
    try {
      return await _speech.initialize(
        onError: _routeError,
        onStatus: _routeStatus,
      );
    } catch (_) {
      return false;
    }
  }

  static void _routeError(SpeechRecognitionError error) =>
      _active?._onError(error);

  static void _routeStatus(String status) => _active?._onStatus(status);

  @override
  Stream<DictationEvent> start() {
    final events = StreamController<DictationEvent>();
    _events = events;
    _active = this;

    _speech
        .listen(
      onResult: (result) {
        if (events.isClosed) return;
        events.add(DictationEvent(
          result.finalResult ? 'final' : 'partial',
          text: result.recognizedWords,
        ));
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        pauseFor: dictationPauseFor,
        listenFor: dictationMaxDuration,
        cancelOnError: true,
      ),
    )
        .catchError((Object e) {
      _emitError('engine-failed');
      _endSession();
    });

    return events.stream;
  }

  void _onError(SpeechRecognitionError error) {
    final code = error.errorMsg;
    // Silence isn't an error for dictation — the session just ends.
    if (code.contains('no-speech') ||
        code.contains('no_match') ||
        code.contains('speech_timeout') ||
        code.contains('aborted')) {
      _endSession();
      return;
    }
    if (code.contains('not-allowed') ||
        code.contains('permission') ||
        code.contains('audio-capture')) {
      _emitError('permission');
    } else if (code.contains('network') ||
        code.contains('service-not-allowed') ||
        code.contains('not_supported') ||
        code.contains('not supported') ||
        code.contains('language-not-supported')) {
      // The API exists but doesn't work here (Brave-style forks) — the
      // controller switches to the recorder fallback on this code.
      _emitError('engine-failed');
    } else {
      _emitError('failed');
    }
    if (error.permanent) _endSession();
  }

  void _onStatus(String status) {
    // 'done' / 'doneNoResult' mark the end of a session (silence auto-stop,
    // listenFor cap, or an explicit stop once final results have flushed).
    if (status.startsWith('done')) _endSession();
  }

  void _emitError(String code) {
    final events = _events;
    if (events == null || events.isClosed) return;
    events.add(DictationEvent('error', errorCode: code));
  }

  void _endSession() {
    final events = _events;
    _events = null;
    if (_active == this) _active = null;
    if (events != null && !events.isClosed) events.close();
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() async {
    await _speech.cancel();
    _endSession();
  }
}

/// Fetches the recorded clip's bytes and content type. On web the `record`
/// plugin's stop() returns a blob URL; an HTTP GET on it yields the blob's
/// bytes with its MIME as Content-Type. Injectable so tests never touch a
/// real blob URL.
typedef BlobFetcher = Future<(Uint8List, String)> Function(String url);

Future<(Uint8List, String)> _httpBlobFetcher(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw Exception('Failed to read recording (HTTP ${response.statusCode})');
  }
  return (
    response.bodyBytes,
    response.headers['content-type'] ?? 'audio/webm',
  );
}

/// Fallback path for browsers without (working) Web Speech: record with
/// MediaRecorder via the `record` plugin, then upload to POST /transcribe.
/// No partials — one final transcript after a `transcribing` event.
///
/// Web-oriented by design: on native platforms the live engine is always
/// available, so this engine is never selected there.
class RecorderEngine implements DictationEngine {
  final TranscribeApiService service;
  final AudioRecorder Function() _newRecorder;
  final BlobFetcher _fetchBlob;

  AudioRecorder? _recorder;
  StreamController<DictationEvent>? _events;
  Timer? _maxTimer;

  RecorderEngine(
    this.service, {
    AudioRecorder Function()? recorderFactory,
    BlobFetcher? blobFetcher,
  })  : _newRecorder = recorderFactory ?? AudioRecorder.new,
        _fetchBlob = blobFetcher ?? _httpBlobFetcher;

  @override
  Future<bool> initialize() async {
    // MediaRecorder is universal in current browsers; whether the *server*
    // side of this path exists is the controller's availability check.
    return true;
  }

  @override
  Stream<DictationEvent> start() {
    final events = StreamController<DictationEvent>();
    _events = events;
    _startRecording(events);
    return events.stream;
  }

  Future<void> _startRecording(StreamController<DictationEvent> events) async {
    final recorder = _newRecorder();
    _recorder = recorder;
    try {
      // Prompts for the microphone on first use.
      if (!await recorder.hasPermission()) {
        events.add(const DictationEvent('error', errorCode: 'permission'));
        await _teardown();
        return;
      }
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus, numChannels: 1),
        path: '', // ignored on web (blob-backed)
      );
      _maxTimer = Timer(dictationMaxDuration, stop);
    } catch (_) {
      if (!events.isClosed) {
        events.add(const DictationEvent('error', errorCode: 'failed'));
      }
      await _teardown();
    }
  }

  @override
  Future<void> stop() async {
    final events = _events;
    final recorder = _recorder;
    if (events == null || events.isClosed || recorder == null) return;
    _maxTimer?.cancel();
    _maxTimer = null;

    try {
      final url = await recorder.stop();
      if (url == null) {
        // Nothing was captured — treat like silence.
        await _teardown();
        return;
      }
      events.add(const DictationEvent('transcribing'));
      final (audio, mimeType) = await _fetchBlob(url);
      final text = await service.transcribe(audio, mimeType);
      if (!events.isClosed && text.trim().isNotEmpty) {
        events.add(DictationEvent('final', text: text.trim()));
      }
    } on TranscribeUnavailableException {
      if (!events.isClosed) {
        events.add(const DictationEvent('error', errorCode: 'unavailable'));
      }
    } catch (_) {
      if (!events.isClosed) {
        events.add(const DictationEvent('error', errorCode: 'failed'));
      }
    }
    await _teardown();
  }

  @override
  Future<void> cancel() async {
    _maxTimer?.cancel();
    _maxTimer = null;
    try {
      await _recorder?.cancel();
    } catch (_) {}
    await _teardown();
  }

  Future<void> _teardown() async {
    final events = _events;
    final recorder = _recorder;
    _events = null;
    _recorder = null;
    if (events != null && !events.isClosed) await events.close();
    await recorder?.dispose();
  }
}
