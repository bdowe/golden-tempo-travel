// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserModel _$UserModelFromJson(Map<String, dynamic> json) => UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      isAdmin: json['is_admin'] as bool? ?? false,
      needsOnboarding: json['needs_onboarding'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      remindersEnabled: json['reminders_enabled'] as bool? ?? true,
      nudgesEnabled: json['nudges_enabled'] as bool? ?? true,
      locale: json['locale'] as String?,
    );

Map<String, dynamic> _$UserModelToJson(UserModel instance) => <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'display_name': instance.displayName,
      'is_admin': instance.isAdmin,
      'needs_onboarding': instance.needsOnboarding,
      'created_at': instance.createdAt.toIso8601String(),
      'reminders_enabled': instance.remindersEnabled,
      'nudges_enabled': instance.nudgesEnabled,
      'locale': instance.locale,
    };

AuthResponse _$AuthResponseFromJson(Map<String, dynamic> json) => AuthResponse(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      token: json['token'] as String,
    );

Map<String, dynamic> _$AuthResponseToJson(AuthResponse instance) =>
    <String, dynamic>{
      'user': instance.user,
      'token': instance.token,
    };
