import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trip.dart';
import 'auth_provider.dart';
import 'trips_provider.dart';

/// Trips shared with the signed-in user as an editor-collaborator (latest
/// version per lineage). Rebuilds on sign-in/out; refresh via
/// ref.refresh(sharedWithMeProvider).
final sharedWithMeProvider = FutureProvider<List<Trip>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return const <Trip>[];
  return ref.read(tripsApiServiceProvider).listSharedWithMe();
});
