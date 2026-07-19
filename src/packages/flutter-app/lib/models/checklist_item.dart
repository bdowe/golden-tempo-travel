import 'package:json_annotation/json_annotation.dart';

part 'checklist_item.g.dart';

/// One row on a trip's packing & prep checklist. Unlike booking-todos, every
/// field here is user-editable regardless of [auto] — [auto] just marks a row
/// as AI-seeded (via the assistant's add_packing_item tool) for display.
@JsonSerializable()
class ChecklistItem {
  final String id;
  final String category; // clothing | documents | electronics | health | general
  final String title;
  final bool checked;
  final int position;
  final bool auto;

  const ChecklistItem({
    required this.id,
    required this.category,
    required this.title,
    this.checked = false,
    this.position = 0,
    this.auto = false,
  });

  ChecklistItem copyWith({String? category, String? title, bool? checked}) =>
      ChecklistItem(
        id: id,
        category: category ?? this.category,
        title: title ?? this.title,
        checked: checked ?? this.checked,
        position: position,
        auto: auto,
      );

  factory ChecklistItem.fromJson(Map<String, dynamic> json) =>
      _$ChecklistItemFromJson(json);
  Map<String, dynamic> toJson() => _$ChecklistItemToJson(this);
}
