import 'package:json_annotation/json_annotation.dart';
import 'itinerary_item.dart';
import 'accommodation.dart';
import 'trip_segment.dart';
import 'booking_todo.dart';

part 'trip.g.dart';

@JsonSerializable(explicitToJson: true)
class Trip {
  final String id;
  final String title;
  final String? summary;
  @JsonKey(name: 'start_date')
  final String? startDate;
  @JsonKey(name: 'end_date')
  final String? endDate;
  final String status;
  @JsonKey(name: 'chat_id')
  final String? chatId;
  @JsonKey(name: 'version_count')
  final int? versionCount;
  final List<String>? cities;
  @JsonKey(name: 'created_at')
  final String createdAt;
  @JsonKey(name: 'updated_at')
  final String updatedAt;
  final List<ItineraryItem>? items;
  final List<Accommodation>? accommodations;
  final List<TripSegment>? segments;
  @JsonKey(name: 'booking_todos')
  final List<BookingTodo>? bookingTodos;

  const Trip({
    required this.id,
    required this.title,
    this.summary,
    this.startDate,
    this.endDate,
    required this.status,
    this.chatId,
    this.versionCount,
    this.cities,
    required this.createdAt,
    required this.updatedAt,
    this.items,
    this.accommodations,
    this.segments,
    this.bookingTodos,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => _$TripFromJson(json);
  Map<String, dynamic> toJson() => _$TripToJson(this);
}
