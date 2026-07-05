import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analytics_api_service.dart';
import 'api_client_provider.dart';

final analyticsApiServiceProvider = Provider<AnalyticsApiService>((ref) {
  return AnalyticsApiService(ref.watch(apiClientProvider));
});
