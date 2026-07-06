import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_route_planner/services/plan_service.dart';

/// A non-200 /plan response (middleware 413, gateway 502, ...) carries no SSE
/// frames. streamPlan must convert it into a synthetic `error` event so the
/// provider's error banner + retry path engages instead of a silent no-reply.
void main() {
  PlanService serviceReturning(int status, String body) => PlanService(
        'http://test/api/v1',
        clientFactory: () => MockClient.streaming((request, bodyStream) async {
          await bodyStream.drain<void>();
          return http.StreamedResponse(
              Stream.value(utf8.encode(body)), status);
        }),
      );

  const history = [
    {'role': 'user', 'content': 'plan athens'}
  ];

  test('JSON 413 becomes an error event carrying the server message',
      () async {
    final events = await serviceReturning(
      413,
      '{"message":"request body too large","status":"error"}',
    ).streamPlan(history).toList();

    expect(events, hasLength(1));
    expect(events.single.type, 'error');
    expect(events.single.data['message'], 'request body too large');
  });

  test('non-JSON error body falls back to a generic HTTP message', () async {
    final events = await serviceReturning(502, '<html>Bad Gateway</html>')
        .streamPlan(history)
        .toList();

    expect(events.single.type, 'error');
    expect(events.single.data['message'], contains('502'));
  });

  test('200 SSE stream still parses events unchanged', () async {
    const sse = 'data: {"type":"text_delta","data":{"text":"hello"}}\n\n'
        'data: {"type":"done","data":{}}\n\n';
    final events =
        await serviceReturning(200, sse).streamPlan(history).toList();

    expect(events.map((e) => e.type).toList(), ['text_delta', 'done']);
    expect(events.first.data['text'], 'hello');
  });
}
