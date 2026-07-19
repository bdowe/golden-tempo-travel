import 'package:json_annotation/json_annotation.dart';

part 'budget.g.dart';

/// The single per-trip budget: one [targetAmount] target in one [currency]
/// (default USD — there is no trip-level currency to inherit) plus server-derived
/// [spent] (sum of every expense) and [remaining] (target − spent, null when no
/// target is set). All expenses are assumed to be in [currency] — there is no
/// cross-currency summing or FX.
@JsonSerializable()
class Budget {
  @JsonKey(name: 'target_amount')
  final double? targetAmount;
  final String currency;
  final double spent;
  final double? remaining;

  const Budget({
    this.targetAmount,
    this.currency = 'USD',
    this.spent = 0,
    this.remaining,
  });

  factory Budget.fromJson(Map<String, dynamic> json) => _$BudgetFromJson(json);
  Map<String, dynamic> toJson() => _$BudgetToJson(this);
}
