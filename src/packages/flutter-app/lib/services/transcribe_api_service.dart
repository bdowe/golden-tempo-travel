import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart';

/// Thrown when the server reports the transcription provider is not
/// configured (503) — callers hide the dictation fallback going forward
/// instead of retrying.
class TranscribeUnavailableException implements Exception {
  @override
  String toString() => 'TranscribeUnavailableException';
}

/// Wraps the voice-dictation fallback endpoints (specs/voice-dictation):
/// POST /transcribe (raw audio bytes -> text) and GET /transcribe/availability.
class TranscribeApiService {
  final ApiClient apiClient;

  TranscribeApiService(this.apiClient);

  /// Whether the server-side transcription fallback is configured. Any
  /// failure reads as unavailable — the mic simply won't offer the fallback.
  Future<bool> availability() async {
    try {
      final response = await apiClient.httpClient
          .get(Uri.parse('${apiClient.baseUrl}/transcribe/availability'),
              headers: apiClient.jsonHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> && decoded['available'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Transcribes a recorded clip. [mimeType] is the recorder's reported
  /// content type passed through verbatim (Chromium emits audio/webm,
  /// Firefox audio/ogg; the server strips codec parameters).
  Future<String> transcribe(Uint8List audio, String mimeType) async {
    final headers = apiClient.jsonHeaders()..['Content-Type'] = mimeType;
    final response = await apiClient.httpClient
        .post(Uri.parse('${apiClient.baseUrl}/transcribe'),
            headers: headers, body: audio)
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 503) throw TranscribeUnavailableException();
    if (response.statusCode != 200) {
      var message = 'Transcription failed (HTTP ${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        final msg = decoded is Map<String, dynamic> ? decoded['message'] : null;
        if (msg is String && msg.isNotEmpty) message = msg;
      } catch (_) {}
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['text'] is! String) {
      throw Exception('Malformed transcription response');
    }
    return decoded['text'] as String;
  }
}
