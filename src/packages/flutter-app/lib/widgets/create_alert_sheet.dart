import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/alerts_provider.dart';
import '../theme/spacing.dart';
import '../utils/money_format.dart';
import '../utils/snack.dart';

/// Bottom sheet that turns the current flight search into a price alert
/// (specs/price-alerts). Seeded with the route/date/cheapest price the
/// traveler is looking at; they pick any-drop or a target price.
class CreateAlertSheet extends ConsumerStatefulWidget {
  final String origin;
  final String destination;
  final String departDate; // YYYY-MM-DD
  final String? returnDate; // YYYY-MM-DD; null = one-way
  final int adults;
  final String cabinClass;
  final String baggage; // personal_item | carry_on | checked
  final double? currentPrice;
  final String? currency;

  const CreateAlertSheet({
    super.key,
    required this.origin,
    required this.destination,
    required this.departDate,
    this.returnDate,
    this.adults = 1,
    this.cabinClass = 'economy',
    this.baggage = 'personal_item',
    this.currentPrice,
    this.currency,
  });

  static Future<void> show(BuildContext context, CreateAlertSheet sheet) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: sheet,
      ),
    );
  }

  @override
  ConsumerState<CreateAlertSheet> createState() => _CreateAlertSheetState();
}

class _CreateAlertSheetState extends ConsumerState<CreateAlertSheet> {
  bool _anyDrop = true;
  int _flexDays = 0;
  late final TextEditingController _targetController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill a plausible target: a bit under the current best fare.
    final seed = widget.currentPrice;
    _targetController = TextEditingController(
      text: seed == null ? '' : (seed * 0.9).floorToDouble().toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    double? target;
    if (!_anyDrop) {
      target = double.tryParse(_targetController.text.trim());
      if (target == null || target <= 0) {
        setState(() => _error = 'Enter a valid target price');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(alertsProvider.notifier).create({
        'origin': widget.origin,
        'destination': widget.destination,
        'depart_date': widget.departDate,
        if (widget.returnDate != null) 'return_date': widget.returnDate,
        'adults': widget.adults,
        'cabin_class': widget.cabinClass,
        if (widget.baggage != 'personal_item') 'baggage': widget.baggage,
        if (_flexDays > 0) 'flex_days': _flexDays,
        if (target != null) 'target_price': target,
        if (widget.currentPrice != null) 'current_price': widget.currentPrice,
        if (widget.currency != null) 'currency': widget.currency,
      });
      if (mounted) {
        Navigator.of(context).pop();
        showSnack(
            context,
            'Watching ${widget.origin} → ${widget.destination} — we\'ll '
            'email you on a drop');
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = widget.currency ?? '';
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Watch this route', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${widget.origin} → ${widget.destination} · ${widget.departDate}'
            '${widget.returnDate != null ? ' → ${widget.returnDate}' : ''}'
            '${widget.adults > 1 ? ' · ${widget.adults} adults' : ''}'
            '${widget.cabinClass != 'economy' ? ' · ${widget.cabinClass.replaceAll('_', ' ')}' : ''}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (widget.currentPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Best price now: ${formatMoney(widget.currentPrice!, cur)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify me on any real price drop'),
            subtitle: const Text('At least 5% and \$5 below the last price'),
            value: _anyDrop,
            onChanged: (v) => setState(() => _anyDrop = v),
          ),
          if (!_anyDrop) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _targetController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Notify me at or below',
                prefixText: cur.isEmpty ? null : '$cur ',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Date flexibility', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Watch a few days around your departure and we\'ll flag the '
            'cheapest one.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final d in const [0, 1, 2, 3])
                ChoiceChip(
                  label: Text(d == 0 ? 'Exact' : '±$d'),
                  selected: _flexDays == d,
                  onSelected:
                      _saving ? null : (_) => setState(() => _flexDays = d),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _create,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(_saving ? 'Creating…' : 'Create alert'),
            ),
          ),
        ],
      ),
    );
  }
}
