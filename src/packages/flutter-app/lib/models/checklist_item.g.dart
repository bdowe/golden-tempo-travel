// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checklist_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChecklistItem _$ChecklistItemFromJson(Map<String, dynamic> json) =>
    ChecklistItem(
      id: json['id'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      checked: json['checked'] as bool? ?? false,
      position: (json['position'] as num?)?.toInt() ?? 0,
      auto: json['auto'] as bool? ?? false,
    );

Map<String, dynamic> _$ChecklistItemToJson(ChecklistItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'category': instance.category,
      'title': instance.title,
      'checked': instance.checked,
      'position': instance.position,
      'auto': instance.auto,
    };
