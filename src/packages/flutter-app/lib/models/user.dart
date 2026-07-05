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

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.isAdmin = false,
    this.needsOnboarding = false,
    required this.createdAt,
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
