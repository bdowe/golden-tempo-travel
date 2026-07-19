import 'package:json_annotation/json_annotation.dart';

part 'expense.g.dart';

/// One manual expense line-item on a trip's budget. [category] is a tag from the
/// backend's bounded set (flights | lodging | food | activities | transport |
/// shopping | general), used only for client-side subtotals — there are no
/// per-category targets. [amount] is assumed to be in the budget's currency.
/// [auto] marks a row as AI-seeded (parallels [ChecklistItem.auto]).
@JsonSerializable()
class Expense {
  final String id;
  final String category;
  final String label;
  final double amount;
  final int position;
  final bool auto;

  const Expense({
    required this.id,
    required this.category,
    required this.label,
    required this.amount,
    this.position = 0,
    this.auto = false,
  });

  Expense copyWith({String? category, String? label, double? amount}) => Expense(
        id: id,
        category: category ?? this.category,
        label: label ?? this.label,
        amount: amount ?? this.amount,
        position: position,
        auto: auto,
      );

  factory Expense.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFromJson(json);
  Map<String, dynamic> toJson() => _$ExpenseToJson(this);
}
