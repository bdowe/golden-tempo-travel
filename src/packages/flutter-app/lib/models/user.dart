import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class UserModel {
  final String id;
  final String email;
  @JsonKey(name: 'display_name')
  final String displayName;
  @JsonKey(name: 'is_admin')
  final bool isAdmin;
  @JsonKey(name: 'needs_onboarding')
  final bool needsOnboarding;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// Email preferences, expressed as opt-INs (true = receiving). Default true
  /// so older payloads without the fields read as opted-in.
  @JsonKey(name: 'reminders_enabled')
  final bool remindersEnabled;
  @JsonKey(name: 'nudges_enabled')
  final bool nudgesEnabled;

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.isAdmin = false,
    this.needsOnboarding = false,
    required this.createdAt,
    this.remindersEnabled = true,
    this.nudgesEnabled = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}

@JsonSerializable()
class AuthResponse {
  final UserModel user;
  final String token;

  const AuthResponse({required this.user, required this.token});

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);
}
