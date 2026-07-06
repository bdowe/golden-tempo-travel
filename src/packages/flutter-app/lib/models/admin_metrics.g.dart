// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminMetrics _$AdminMetricsFromJson(Map<String, dynamic> json) => AdminMetrics(
      days: (json['days'] as num?)?.toInt() ?? 30,
      signups: (json['signups'] as num?)?.toInt() ?? 0,
      activatedSignups: (json['activated_signups'] as num?)?.toInt() ?? 0,
      activationRate: (json['activation_rate'] as num?)?.toDouble() ?? 0,
      onboardingsCompleted:
          (json['onboardings_completed'] as num?)?.toInt() ?? 0,
      tripsCreated: (json['trips_created'] as num?)?.toInt() ?? 0,
      tripsRefined: (json['trips_refined'] as num?)?.toInt() ?? 0,
      tripsWithBookingClick:
          (json['trips_with_booking_click'] as num?)?.toInt() ?? 0,
      attachRate: (json['attach_rate'] as num?)?.toDouble() ?? 0,
      bookingClicks: (json['booking_clicks'] as num?)?.toInt() ?? 0,
      clicksByProvider:
          (json['clicks_by_provider'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, (e as num).toInt()),
              ) ??
              const {},
      todosMarkedBooked: (json['todos_marked_booked'] as num?)?.toInt() ?? 0,
      secondTripRetention:
          (json['second_trip_retention'] as num?)?.toInt() ?? 0,
      sessionFrequencyReturning:
          (json['session_frequency_returning'] as num?)?.toInt() ?? 0,
      activeUsers: (json['active_users'] as num?)?.toInt() ?? 0,
      planSessions: (json['plan_sessions'] as num?)?.toInt() ?? 0,
      planSessionsAnonymous:
          (json['plan_sessions_anonymous'] as num?)?.toInt() ?? 0,
      agentLoopCapHits: (json['agent_loop_cap_hits'] as num?)?.toInt() ?? 0,
      planInputTokens: (json['plan_input_tokens'] as num?)?.toInt() ?? 0,
      planOutputTokens: (json['plan_output_tokens'] as num?)?.toInt() ?? 0,
      planCacheReadTokens:
          (json['plan_cache_read_tokens'] as num?)?.toInt() ?? 0,
      planCacheCreationTokens:
          (json['plan_cache_creation_tokens'] as num?)?.toInt() ?? 0,
      estClaudeCostUsd: (json['est_claude_cost_usd'] as num?)?.toDouble() ?? 0,
      estCogsPerActiveUser:
          (json['est_cogs_per_active_user'] as num?)?.toDouble() ?? 0,
      alertsCreated: (json['alerts_created'] as num?)?.toInt() ?? 0,
      alertsTriggered: (json['alerts_triggered'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$AdminMetricsToJson(AdminMetrics instance) =>
    <String, dynamic>{
      'days': instance.days,
      'signups': instance.signups,
      'activated_signups': instance.activatedSignups,
      'activation_rate': instance.activationRate,
      'onboardings_completed': instance.onboardingsCompleted,
      'trips_created': instance.tripsCreated,
      'trips_refined': instance.tripsRefined,
      'trips_with_booking_click': instance.tripsWithBookingClick,
      'attach_rate': instance.attachRate,
      'booking_clicks': instance.bookingClicks,
      'clicks_by_provider': instance.clicksByProvider,
      'todos_marked_booked': instance.todosMarkedBooked,
      'second_trip_retention': instance.secondTripRetention,
      'session_frequency_returning': instance.sessionFrequencyReturning,
      'active_users': instance.activeUsers,
      'plan_sessions': instance.planSessions,
      'plan_sessions_anonymous': instance.planSessionsAnonymous,
      'agent_loop_cap_hits': instance.agentLoopCapHits,
      'plan_input_tokens': instance.planInputTokens,
      'plan_output_tokens': instance.planOutputTokens,
      'plan_cache_read_tokens': instance.planCacheReadTokens,
      'plan_cache_creation_tokens': instance.planCacheCreationTokens,
      'est_claude_cost_usd': instance.estClaudeCostUsd,
      'est_cogs_per_active_user': instance.estCogsPerActiveUser,
      'alerts_created': instance.alertsCreated,
      'alerts_triggered': instance.alertsTriggered,
    };
