import 'trip.dart';

/// Public read-only view of a shared trip: the latest version of the trip's
/// lineage plus attribution to its owner. Plain model (composes [Trip], which
/// does the json_serializable work).
class SharedTrip {
  final Trip trip;
  final String ownerName;

  /// Role of the link this trip was opened with: 'viewer' (read-only,
  /// save-a-copy) or 'editor' (offers "Join as co-planner").
  final String role;

  const SharedTrip({
    required this.trip,
    required this.ownerName,
    this.role = 'viewer',
  });

  bool get isEditorLink => role == 'editor';

  factory SharedTrip.fromJson(Map<String, dynamic> json) => SharedTrip(
        trip: Trip.fromJson(json['trip'] as Map<String, dynamic>),
        ownerName: (json['owner_name'] as String?) ?? 'A traveler',
        role: (json['role'] as String?) ?? 'viewer',
      );
}
