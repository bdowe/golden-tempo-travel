import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/providers/plan_provider.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/plan_service.dart';

/// Emits [deltaCount] text_delta events a couple of milliseconds apart —
/// far faster than the notifier's flush interval, like the real SSE stream.
class _FakePlanService extends PlanService {
  final int deltaCount;

  _FakePlanService(this.deltaCount) : super('http://unused');

  @override
  Stream<PlanEvent> streamPlan(
    List<Map<String, String>> messages, {
    String? bearerToken,
    String? chatId,
    String? tripId,
  }) async* {
    for (var i = 0; i < deltaCount; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      yield PlanEvent(type: 'text_delta', data: {'text': 'tok$i '});
    }
  }
}

void main() {
  test('text deltas are coalesced into far fewer state emissions', () async {
    const deltas = 60;
    final notifier = PlanNotifier(_FakePlanService(deltas), ApiClient());

    var streamingEmissions = 0;
    String? lastStreaming;
    notifier.addListener((state) {
      if (state.streamingText != lastStreaming) {
        lastStreaming = state.streamingText;
        if (state.streamingText != null) streamingEmissions++;
      }
    });

    await notifier.sendMessage('hi');

    // ~120ms of 2ms-apart deltas against a 48ms flush interval → a handful of
    // emissions, never one per token.
    expect(streamingEmissions, greaterThan(0));
    expect(streamingEmissions, lessThan(deltas ~/ 3));

    // No token lost to coalescing: the committed message is the concatenation.
    final expected = List.generate(deltas, (i) => 'tok$i ').join();
    expect(notifier.state.messages.last.content, expected);
    expect(notifier.state.isStreaming, isFalse);
    expect(notifier.state.streamingText, isNull);

    // A late flush timer must not resurrect a ghost streaming bubble.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(notifier.state.streamingText, isNull);
  });
}
