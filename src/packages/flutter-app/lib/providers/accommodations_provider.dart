import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/accommodations_api_service.dart';
import 'api_client_provider.dart';

final accommodationsApiServiceProvider = Provider<AccommodationsApiService>((ref) {
  return AccommodationsApiService(ref.watch(apiClientProvider));
});
