import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../models/airport.dart';
import '../providers/flights_provider.dart';

/// An airport/city autocomplete field backed by [airportSearchProvider]. When a
/// place is selected it shows the chosen label with a clear button; otherwise it
/// shows a search box with a live suggestion dropdown. Shared by the Find
/// Flights screen and the Travel profile (home airport).
class AirportField extends ConsumerStatefulWidget {
  final String label;
  final IconData icon;
  final Airport? selected;
  final ValueChanged<Airport?> onSelected;

  const AirportField({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  ConsumerState<AirportField> createState() => _AirportFieldState();
}

class _AirportFieldState extends ConsumerState<AirportField> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = widget.selected;

    if (selected != null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: Icon(widget.icon),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              widget.onSelected(null);
              _controller.clear();
              setState(() => _query = '');
            },
          ),
        ),
        child: Text(selected.label,
            style: const TextStyle(fontWeight: FontWeight.w500)),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: l10n.airportFieldHint,
            prefixIcon: Icon(widget.icon),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        if (_query.trim().length >= 2)
          Consumer(
            builder: (context, ref, _) {
              final results = ref.watch(airportSearchProvider(_query));
              return results.when(
                data: (airports) => airports.isEmpty
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: airports
                              .map((a) => ListTile(
                                    dense: true,
                                    leading: Icon(
                                        a.subType.toLowerCase() == 'city'
                                            ? Icons.location_city
                                            : Icons.local_airport,
                                        size: 20),
                                    title: Text(a.label),
                                    subtitle: a.country.isEmpty
                                        ? null
                                        : Text(a.country),
                                    onTap: () {
                                      widget.onSelected(a);
                                      _controller.clear();
                                      setState(() => _query = '');
                                    },
                                  ))
                              .toList(),
                        ),
                      ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                ),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
      ],
    );
  }
}
