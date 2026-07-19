import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/checklist_item.dart';
import '../providers/checklist_provider.dart';
import '../theme/spacing.dart';
import 'empty_state.dart';
import 'section_header.dart';
import 'status_pill.dart';

/// The trip-detail "Packing & prep" section: a lightweight per-trip checklist
/// the AI assistant seeds (add_packing_item) and the traveler edits freely.
/// Self-contained — it owns its data via [checklistProvider] and reconciles
/// mutations by invalidating that family key.
class ChecklistSection extends ConsumerStatefulWidget {
  final String tripId;
  final bool canEdit;
  final bool isOffline;

  const ChecklistSection({
    super.key,
    required this.tripId,
    required this.canEdit,
    required this.isOffline,
  });

  @override
  ConsumerState<ChecklistSection> createState() => _ChecklistSectionState();
}

// Display order + labels for the category groups. Free-text on the server, but
// the client groups into this known set; anything else falls under "General".
const List<String> _categoryOrder = [
  'documents',
  'clothing',
  'electronics',
  'health',
  'general',
];

const Map<String, String> _categoryLabels = {
  'documents': 'Documents',
  'clothing': 'Clothing',
  'electronics': 'Electronics',
  'health': 'Health',
  'general': 'General',
};

const Map<String, IconData> _categoryIcons = {
  'documents': Icons.description_outlined,
  'clothing': Icons.checkroom_outlined,
  'electronics': Icons.devices_other_outlined,
  'health': Icons.medical_services_outlined,
  'general': Icons.luggage_outlined,
};

String _normalizeCategory(String raw) {
  final c = raw.trim().toLowerCase();
  return _categoryLabels.containsKey(c) ? c : 'general';
}

class _ChecklistSectionState extends ConsumerState<ChecklistSection> {
  final TextEditingController _addController = TextEditingController();
  String _addCategory = 'general';
  bool _busy = false;

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  bool _guard() {
    if (widget.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("You're offline — reconnect to make changes.")),
      );
      return true;
    }
    return false;
  }

  Future<void> _run(Future<void> Function() op) async {
    if (_guard() || _busy) return;
    setState(() => _busy = true);
    try {
      await op();
      ref.invalidate(checklistProvider(widget.tripId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggle(ChecklistItem item, bool checked) => _run(() =>
      ref.read(checklistApiServiceProvider).update(
          widget.tripId, item.id, {'checked': checked}));

  void _delete(ChecklistItem item) => _run(() =>
      ref.read(checklistApiServiceProvider).delete(widget.tripId, item.id));

  void _add() {
    final title = _addController.text.trim();
    if (title.isEmpty) return;
    _run(() async {
      await ref
          .read(checklistApiServiceProvider)
          .add(widget.tripId, title, _addCategory);
      _addController.clear();
    });
  }

  Future<void> _editTitle(ChecklistItem item) async {
    if (_guard()) return;
    final controller = TextEditingController(text: item.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit item'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Item'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && newTitle != item.title) {
      _run(() => ref
          .read(checklistApiServiceProvider)
          .update(widget.tripId, item.id, {'title': newTitle}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(checklistProvider(widget.tripId));
    // Best-effort: on error or while first loading with no data, render
    // nothing rather than an error state — a utility section shouldn't shout.
    final items = async.valueOrNull;
    if (items == null) return const SizedBox.shrink();

    // Viewers with an empty list get no section at all (nothing to show or do).
    if (items.isEmpty && !widget.canEdit) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final checked = items.where((i) => i.checked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        SectionHeader(
          title: 'Packing & prep',
          action: items.isEmpty
              ? null
              : StatusPill.custom(
                  label: '$checked/${items.length}',
                  background: theme.colorScheme.surfaceContainerHighest,
                  foreground: theme.colorScheme.onSurfaceVariant,
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.luggage_outlined,
            title: 'Nothing packed yet',
            message:
                'Add items below, or ask the AI assistant to help build your list.',
          )
        else
          ..._buildGroups(theme, items),
        if (widget.canEdit) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildAddRow(theme),
        ],
      ],
    );
  }

  List<Widget> _buildGroups(ThemeData theme, List<ChecklistItem> items) {
    final byCategory = <String, List<ChecklistItem>>{};
    for (final item in items) {
      byCategory.putIfAbsent(_normalizeCategory(item.category), () => []).add(item);
    }
    final widgets = <Widget>[];
    for (final cat in _categoryOrder) {
      final group = byCategory[cat];
      if (group == null || group.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
        child: Row(
          children: [
            Icon(_categoryIcons[cat], size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Text(
              _categoryLabels[cat]!,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ));
      for (final item in group) {
        widgets.add(_buildRow(theme, item));
      }
    }
    return widgets;
  }

  Widget _buildRow(ThemeData theme, ChecklistItem item) {
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: Checkbox(
              value: item.checked,
              onChanged: widget.canEdit
                  ? (v) => _toggle(item, v ?? false)
                  : null,
            ),
          ),
          Expanded(
            child: Text(
              item.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration:
                    item.checked ? TextDecoration.lineThrough : null,
                color: item.checked
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (widget.canEdit)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
              tooltip: 'Item options',
              onSelected: (v) {
                if (v == 'edit') _editTitle(item);
                if (v == 'delete') _delete(item);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAddRow(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DropdownButton<String>(
          value: _addCategory,
          underline: const SizedBox.shrink(),
          onChanged: widget.isOffline
              ? null
              : (v) => setState(() => _addCategory = v ?? 'general'),
          items: [
            for (final cat in _categoryOrder)
              DropdownMenuItem(
                value: cat,
                child: Icon(_categoryIcons[cat],
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: _addController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Add an item…',
            ),
            onSubmitted: (_) => _add(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Add item',
          onPressed: widget.isOffline ? null : _add,
        ),
      ],
    );
  }
}
