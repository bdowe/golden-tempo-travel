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

  /// Users with >= 2 trip_created events >= 7 days apart in the window —
  /// the business model's "returned for a second trip" retention signal.
  @JsonKey(name: 'second_trip_retention')
  final int secondTripRetention;

  /// Users with plan sessions on >= 2 distinct days (session frequency,
  /// NOT trip retention — formerly `returning_users`).
  @JsonKey(name: 'session_frequency_returning')
  final int sessionFrequencyReturning;

  /// MAU: distinct signed-in users with >= 1 plan session in the window.
  @JsonKey(name: 'active_users')
  final int activeUsers;
  @JsonKey(name: 'plan_sessions')
  final int planSessions;
  @JsonKey(name: 'plan_sessions_anonymous')
  final int planSessionsAnonymous;

  /// Sessions whose agent loop hit the max-iterations safety cap (a
  /// runaway-loop signal — formerly `plan_cap_hits`).
  @JsonKey(name: 'agent_loop_cap_hits')
  final int agentLoopCapHits;
  @JsonKey(name: 'plan_input_tokens')
  final int planInputTokens;
  @JsonKey(name: 'plan_output_tokens')
  final int planOutputTokens;
  @JsonKey(name: 'plan_cache_read_tokens')
  final int planCacheReadTokens;
  @JsonKey(name: 'plan_cache_creation_tokens')
  final int planCacheCreationTokens;

  /// Estimated Claude spend for the window in USD (Claude only — Places
  /// calls are not counted).
  @JsonKey(name: 'est_claude_cost_usd')
  final double estClaudeCostUsd;

  /// estClaudeCostUsd / activeUsers — the §8 COGS-per-active-user estimate.
  @JsonKey(name: 'est_cogs_per_active_user')
  final double estCogsPerActiveUser;
  @JsonKey(name: 'alerts_created')
  final int alertsCreated;
  @JsonKey(name: 'alerts_triggered')
  final int alertsTriggered;

  /// Free-cap would-hit crossings per cap kind (plan_runs / active_trips) —
  /// the Phase-3 demand signal. Measurement only; nothing is enforced.
  @JsonKey(name: 'free_cap_would_hits')
  final Map<String, int> freeCapWouldHits;

  /// Distinct users who crossed each cap at least once in the window — the
  /// cohort size the paid-tier trigger reads.
  @JsonKey(name: 'free_cap_users_affected')
  final Map<String, int> freeCapUsersAffected;

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
    this.secondTripRetention = 0,
    this.sessionFrequencyReturning = 0,
    this.activeUsers = 0,
    this.planSessions = 0,
    this.planSessionsAnonymous = 0,
    this.agentLoopCapHits = 0,
    this.planInputTokens = 0,
    this.planOutputTokens = 0,
    this.planCacheReadTokens = 0,
    this.planCacheCreationTokens = 0,
    this.estClaudeCostUsd = 0,
    this.estCogsPerActiveUser = 0,
    this.alertsCreated = 0,
    this.alertsTriggered = 0,
    this.freeCapWouldHits = const {},
    this.freeCapUsersAffected = const {},
  });

  factory AdminMetrics.fromJson(Map<String, dynamic> json) =>
      _$AdminMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$AdminMetricsToJson(this);
}
