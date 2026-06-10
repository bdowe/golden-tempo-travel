import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/plan_message.dart';
import '../models/location.dart';
import '../models/flight_offer.dart';
import '../services/api_client.dart';
import '../services/plan_service.dart';
import 'api_client_provider.dart';

class PlanState {
  final List<PlanMessage> messages;
  final bool isStreaming;
  final String? streamingText;
  final List<String> activeTools;
  final List<Map<String, dynamic>>? completedLocations;
  final String? completedSummary;
  final String? savedTripId;
  final List<FlightOffer>? flightOffers;
  final String? flightRouteLabel;
  final String? error;

  const PlanState({
    this.messages = const [],
    this.isStreaming = false,
    this.streamingText,
    this.activeTools = const [],
    this.completedLocations,
    this.completedSummary,
    this.savedTripId,
    this.flightOffers,
    this.flightRouteLabel,
    this.error,
  });

  PlanState copyWith({
    List<PlanMessage>? messages,
    bool? isStreaming,
    Object? streamingText = _sentinel,
    List<String>? activeTools,
    Object? completedLocations = _sentinel,
    Object? completedSummary = _sentinel,
    Object? savedTripId = _sentinel,
    Object? flightOffers = _sentinel,
    Object? flightRouteLabel = _sentinel,
    Object? error = _sentinel,
  }) {
    return PlanState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      streamingText: streamingText == _sentinel ? this.streamingText : streamingText as String?,
      activeTools: activeTools ?? this.activeTools,
      completedLocations: completedLocations == _sentinel
          ? this.completedLocations
          : completedLocations as List<Map<String, dynamic>>?,
      completedSummary: completedSummary == _sentinel ? this.completedSummary : completedSummary as String?,
      savedTripId: savedTripId == _sentinel ? this.savedTripId : savedTripId as String?,
      flightOffers: flightOffers == _sentinel ? this.flightOffers : flightOffers as List<FlightOffer>?,
      flightRouteLabel: flightRouteLabel == _sentinel ? this.flightRouteLabel : flightRouteLabel as String?,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

class PlanNotifier extends StateNotifier<PlanState> {
  final PlanService _service;
  final ApiClient _apiClient;

  // Stable id for the current conversation. Every create_itinerary in this chat
  // is stamped with it server-side so refinements collapse to one trip in My
  // Trips instead of spawning duplicate drafts. Regenerated on reset().
  String? _chatId;

  PlanNotifier(this._service, this._apiClient) : super(const PlanState());

  // 0x7fffffff (not 1 << 32) because on the web target `1 << 32` overflows JS's
  // 32-bit bitwise ops to 0, and Random.nextInt(0) throws RangeError.
  static String _newChatId() =>
      'chat-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

  List<Location> get completedAsLocations {
    final locs = state.completedLocations;
    if (locs == null) return [];
    return locs.asMap().entries.map((entry) {
      final i = entry.key;
      final loc = entry.value;
      final lat = (loc['latitude'] as num?)?.toDouble();
      final lng = (loc['longitude'] as num?)?.toDouble();
      final placeId = loc['place_id'] as String?;
      return Location(
        id: placeId ?? 'agent-loc-$i',
        name: loc['name'] as String? ?? 'Location ${i + 1}',
        placeId: placeId,
        latitude: lat,
        longitude: lng,
        address: loc['address'] as String?,
      );
    }).toList();
  }

  Future<void> sendMessage(String text) async {
    if (state.isStreaming) return;

    _chatId ??= _newChatId();

    final userMessage = PlanMessage(role: MessageRole.user, content: text);
    final updatedMessages = [...state.messages, userMessage];

    state = state.copyWith(
      messages: updatedMessages,
      isStreaming: true,
      streamingText: '',
      activeTools: [],
      flightOffers: null,
      flightRouteLabel: null,
      error: null,
    );

    final history = updatedMessages
        .map((m) => {'role': m.role == MessageRole.user ? 'user' : 'assistant', 'content': m.content})
        .toList();

    final textBuffer = StringBuffer();

    try {
      await for (final event in _service.streamPlan(history, bearerToken: _apiClient.authToken, chatId: _chatId)) {
        switch (event.type) {
          case 'text_delta':
            textBuffer.write(event.data['text'] as String? ?? '');
            state = state.copyWith(streamingText: textBuffer.toString());

          case 'tool_call':
            final name = event.data['name'] as String? ?? '';
            state = state.copyWith(activeTools: [...state.activeTools, name]);

          case 'tool_result':
            final name = event.data['name'] as String? ?? '';
            final tools = state.activeTools.toList()..remove(name);
            state = state.copyWith(activeTools: tools);

          case 'done':
            final rawLocs = event.data['locations'] as List<dynamic>? ?? [];
            final locations = rawLocs.cast<Map<String, dynamic>>();
            final summary = event.data['summary'] as String?;
            state = state.copyWith(
              completedLocations: locations,
              completedSummary: summary,
              savedTripId: event.data['trip_id'] as String?,
            );

          case 'flights':
            final raw = event.data['offers'] as List<dynamic>? ?? [];
            final offers = raw
                .map((e) => FlightOffer.fromJson(e as Map<String, dynamic>))
                .toList();
            final origin = event.data['origin'] as String? ?? '';
            final dest = event.data['destination'] as String? ?? '';
            state = state.copyWith(
              flightOffers: offers,
              flightRouteLabel: '$origin → $dest',
            );

          case 'error':
            state = state.copyWith(
              isStreaming: false,
              streamingText: null,
              activeTools: [],
              error: event.data['message'] as String? ?? 'Unknown error',
            );
            return;
        }
      }

      // Commit streamed assistant text as a message
      final assistantText = textBuffer.toString();
      if (assistantText.isNotEmpty) {
        state = state.copyWith(
          messages: [
            ...state.messages,
            PlanMessage(role: MessageRole.assistant, content: assistantText),
          ],
        );
      }

      state = state.copyWith(
        isStreaming: false,
        streamingText: null,
        activeTools: [],
      );
    } catch (e) {
      state = state.copyWith(
        isStreaming: false,
        streamingText: null,
        activeTools: [],
        error: e.toString(),
      );
    }
  }

  void reset() {
    _chatId = null;
    state = const PlanState();
  }

  /// Reopen a saved trip for refinement: clears any prior conversation, binds the
  /// session to the trip's chat group so new itineraries persist as versions of
  /// it, then sends the seed describing the current itinerary.
  void beginRefinement({required String chatId, required String seedMessage}) {
    reset();
    _chatId = chatId;
    sendMessage(seedMessage);
  }
}

final planProvider = StateNotifierProvider<PlanNotifier, PlanState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PlanNotifier(PlanService(apiClient.baseUrl), apiClient);
});
