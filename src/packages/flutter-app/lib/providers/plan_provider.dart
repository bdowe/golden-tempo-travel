import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/plan_message.dart';
import '../models/location.dart';
import '../models/flight_offer.dart';
import '../models/event.dart';
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
  final List<Event>? eventResults;
  final String? eventsCityLabel;
  final String? error;

  /// Short excerpt of profile notes the agent just saved (server
  /// `profile_updated` event); shown as a transient "Noted" chip in the chat.
  final String? profileUpdateNote;

  /// Bumped each time a trip-bound session patches the trip in place
  /// (server `trip_updated` event); listeners reload the trip when it grows.
  final int tripUpdateCount;

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
    this.eventResults,
    this.eventsCityLabel,
    this.error,
    this.profileUpdateNote,
    this.tripUpdateCount = 0,
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
    Object? eventResults = _sentinel,
    Object? eventsCityLabel = _sentinel,
    Object? error = _sentinel,
    Object? profileUpdateNote = _sentinel,
    int? tripUpdateCount,
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
      eventResults: eventResults == _sentinel ? this.eventResults : eventResults as List<Event>?,
      eventsCityLabel: eventsCityLabel == _sentinel ? this.eventsCityLabel : eventsCityLabel as String?,
      error: error == _sentinel ? this.error : error as String?,
      profileUpdateNote:
          profileUpdateNote == _sentinel ? this.profileUpdateNote : profileUpdateNote as String?,
      tripUpdateCount: tripUpdateCount ?? this.tripUpdateCount,
    );
  }
}

const _sentinel = Object();

class PlanNotifier extends StateNotifier<PlanState> {
  final PlanService _service;
  final ApiClient _apiClient;

  /// When set, every request carries trip_id and the server refines that saved
  /// trip in place (update_itinerary_section) instead of creating new versions.
  final String? tripId;

  // Stable id for the current conversation. Every create_itinerary in this chat
  // is stamped with it server-side so refinements collapse to one trip in My
  // Trips instead of spawning duplicate drafts. Regenerated on reset().
  String? _chatId;

  PlanNotifier(this._service, this._apiClient, {this.tripId}) : super(const PlanState());

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
      eventResults: null,
      eventsCityLabel: null,
      error: null,
      profileUpdateNote: null,
    );

    final history = updatedMessages
        .map((m) => {'role': m.role == MessageRole.user ? 'user' : 'assistant', 'content': m.content})
        .toList();

    final textBuffer = StringBuffer();

    try {
      await for (final event in _service.streamPlan(history,
          bearerToken: _apiClient.authToken, chatId: _chatId, tripId: tripId)) {
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

            case 'trip_updated':
            state = state.copyWith(tripUpdateCount: state.tripUpdateCount + 1);

          case 'profile_updated':
            state = state.copyWith(
                profileUpdateNote: event.data['notes_preview'] as String? ?? '');

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

          case 'events':
            final raw = event.data['events'] as List<dynamic>? ?? [];
            final events = raw
                .map((e) => Event.fromJson(e as Map<String, dynamic>))
                .toList();
            state = state.copyWith(
              eventResults: events,
              eventsCityLabel: event.data['city'] as String?,
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

  /// Start (or restart) an in-place section refinement on the bound trip:
  /// clears any prior conversation and sends the seed describing the targeted
  /// section. Requires [tripId]; the server patches that trip directly, so no
  /// chat-group binding is needed.
  void beginSectionRefinement(String seedMessage) {
    reset();
    sendMessage(seedMessage);
  }
}

final planProvider = StateNotifierProvider<PlanNotifier, PlanState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PlanNotifier(PlanService(apiClient.baseUrl), apiClient);
});

/// Per-trip refinement session for the trip-detail panel, kept separate from
/// the global [planProvider] so panel chats never clobber the Agent tab's
/// conversation. keepAlive preserves the conversation across panel
/// close/reopen while the app runs; it is reset explicitly when a new
/// refinement target is chosen.
final tripRefineProvider = StateNotifierProvider.family<PlanNotifier, PlanState, String>((ref, tripId) {
  final apiClient = ref.watch(apiClientProvider);
  return PlanNotifier(PlanService(apiClient.baseUrl), apiClient, tripId: tripId);
});
