import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/booking_todos_api_service.dart';
import 'api_client_provider.dart';

final bookingTodosApiServiceProvider = Provider<BookingTodosApiService>((ref) {
  return BookingTodosApiService(ref.watch(apiClientProvider));
});
