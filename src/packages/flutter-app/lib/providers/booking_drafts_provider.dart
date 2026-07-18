import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/booking_drafts_api_service.dart';
import 'api_client_provider.dart';

final bookingDraftsApiServiceProvider =
    Provider<BookingDraftsApiService>((ref) {
  return BookingDraftsApiService(ref.watch(apiClientProvider));
});
