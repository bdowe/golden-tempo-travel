import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/transcribe_api_service.dart';

TranscribeApiService _service(MockClient client) {
  return TranscribeApiService(
      ApiClient(baseUrl: 'http://test/api/v1', client: client));
}

void main() {
  test('transcribe POSTs raw bytes with the recorder MIME passed through',
      () async {
    late http.Request captured;
    final service = _service(MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'text': 'hello', 'status': 'success'}),
          200,
          headers: {'content-type': 'application/json'});
    }));

    final audio = Uint8List.fromList([1, 2, 3, 4]);
    final text = await service.transcribe(audio, 'audio/ogg; codecs=opus');

    expect(text, 'hello');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/transcribe');
    expect(captured.headers['Content-Type'], startsWith('audio/ogg'));
    expect(captured.bodyBytes, audio);
  });

  test('a 503 surfaces as TranscribeUnavailableException', () async {
    final service = _service(MockClient((request) async {
      return http.Response(
          jsonEncode({'message': 'Transcription is not configured'}), 503);
    }));

    expect(() => service.transcribe(Uint8List.fromList([1]), 'audio/webm'),
        throwsA(isA<TranscribeUnavailableException>()));
  });

  test('other errors surface the server message', () async {
    final service = _service(MockClient((request) async {
      return http.Response(
          jsonEncode({'message': 'Failed to transcribe audio'}), 502);
    }));

    expect(
        () => service.transcribe(Uint8List.fromList([1]), 'audio/webm'),
        throwsA(predicate(
            (e) => e.toString().contains('Failed to transcribe audio'))));
  });

  test('availability parses the flag and fails closed', () async {
    for (final (body, code, want) in [
      ('{"available": true}', 200, true),
      ('{"available": false}', 200, false),
      ('oops', 200, false),
      ('{"available": true}', 500, false),
    ]) {
      final service =
          _service(MockClient((request) async => http.Response(body, code)));
      expect(await service.availability(), want,
          reason: 'body=$body code=$code');
    }
  });
}
