import 'package:json_annotation/json_annotation.dart';

part 'admin_metrics.g.dart';

/// Mirror of the API's MetricsResponse (GET /admin/metrics?days=) — the
/// Phase-1 growth funnel: activation, attach rate, retention, AI cost.
@JsonSerializable()
class AdminMetrics {
  final int days;
  final int signups;
  @JsonKey(name: 'activated_signups')
  final int activatedSignups;
  @JsonKey(name: 'activation_rate')
  final double activationRate;
  @JsonKey(name: 'onboardings_completed')
  final int onboardingsCompleted;
  @JsonKey(name: 'trips_created')
  final int tripsCreated;
  @JsonKey(name: 'trips_refined')
  final int tripsRefined;
  @JsonKey(name: 'trips_with_booking_click')
  final int tripsWithBookingClick;
  @JsonKey(name: 'attach_rate')
  final double attachRate;
  @JsonKey(name: 'booking_clicks')
  final int bookingClicks;
  @JsonKey(name: 'clicks_by_provider')
  final Map<String, int> clicksByProvider;
  @JsonKey(name: 'todos_marked_booked')
  final int todosMarkedBooked;
  @JsonKey(name: 'returning_users')
  final int returningUsers;
  @JsonKey(name: 'plan_sessions')
  final int planSessions;
  @JsonKey(name: 'plan_sessions_anonymous')
  final int planSessionsAnonymous;
  @JsonKey(name: 'plan_cap_hits')
  final int planCapHits;
  @JsonKey(name: 'plan_input_tokens')
  final int planInputTokens;
  @JsonKey(name: 'plan_output_tokens')
  final int planOutputTokens;
  @JsonKey(name: 'plan_cache_read_tokens')
  final int planCacheReadTokens;
  @JsonKey(name: 'plan_cache_creation_tokens')
  final int planCacheCreationTokens;
  @JsonKey(name: 'alerts_created')
  final int alertsCreated;
  @JsonKey(name: 'alerts_triggered')
  final int alertsTriggered;

  const AdminMetrics({
    this.days = 30,
    this.signups = 0,
    this.activatedSignups = 0,
    this.activationRate = 0,
    this.onboardingsCompleted = 0,
    this.tripsCreated = 0,
    this.tripsRefined = 0,
    this.tripsWithBookingClick = 0,
    this.attachRate = 0,
    this.bookingClicks = 0,
    this.clicksByProvider = const {},
    this.todosMarkedBooked = 0,
    this.returningUsers = 0,
    this.planSessions = 0,
    this.planSessionsAnonymous = 0,
    this.planCapHits = 0,
    this.planInputTokens = 0,
    this.planOutputTokens = 0,
    this.planCacheReadTokens = 0,
    this.planCacheCreationTokens = 0,
    this.alertsCreated = 0,
    this.alertsTriggered = 0,
  });

  factory AdminMetrics.fromJson(Map<String, dynamic> json) =>
      _$AdminMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$AdminMetricsToJson(this);
}
