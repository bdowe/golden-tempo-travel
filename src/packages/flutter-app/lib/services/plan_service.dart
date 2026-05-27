import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PlanEvent {
  final String type;
  final Map<String, dynamic> data;

  const PlanEvent({required this.type, required this.data});
}

class PlanService {
  final String baseUrl;

  PlanService(this.baseUrl);

  Stream<PlanEvent> streamPlan(List<Map<String, String>> messages) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/plan'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({'messages': messages});

    final response = await request.send();

    final buffer = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      final raw = buffer.toString();
      final parts = raw.split('\n\n');
      buffer.clear();
      buffer.write(parts.last);

      for (final part in parts.sublist(0, parts.length - 1)) {
        for (final line in part.split('\n')) {
          if (line.startsWith('data: ')) {
            final decoded = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            yield PlanEvent(
              type: decoded['type'] as String,
              data: (decoded['data'] as Map<String, dynamic>?) ?? {},
            );
          }
        }
      }
    }
  }
}
