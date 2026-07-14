import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_route_planner/services/plan_service.dart';

/// The request body carries `summary` only when a compacted summary exists —
/// absent (not empty/null) otherwise, so the server-side presence check works.
void main() {
  const sse = 'data: {"type":"done","data":{}}\n\n';
  const history = [
    {'role': 'user', 'content': 'plan athens'}
  ];

  Future<Map<String, dynamic>> capturedBody({String? summary}) async {
    late Map<String, dynamic> body;
    final service = PlanService(
      'http://test/api/v1',
      clientFactory: () => MockClient.streaming((request, bodyStream) async {
        body = jsonDecode(await utf8.decodeStream(bodyStream))
            as Map<String, dynamic>;
        return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
      }),
    );
    await service.streamPlan(history, summary: summary).toList();
    return body;
  }

  test('summary is serialized when present', () async {
    final body = await capturedBody(summary: '- travelers: 3');
    expect(body['summary'], '- travelers: 3');
    expect(body['messages'], hasLength(1));
  });

  test('summary key is absent when null or empty', () async {
    expect(await capturedBody(), isNot(contains('summary')));
    expect(await capturedBody(summary: ''), isNot(contains('summary')));
  });
}
