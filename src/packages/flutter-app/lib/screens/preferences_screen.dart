import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/airport.dart';
import '../widgets/airport_field.dart';
import '../widgets/gradient_app_bar.dart';
import '../providers/preferences_provider.dart';

const _budgets = ['budget', 'mid', 'luxury'];
const _paces = ['relaxed', 'balanced', 'packed'];
const _suggestedInterests = [
  'museums', 'food', 'nightlife', 'nature', 'history', 'art', 'shopping', 'outdoors', 'beaches', 'architecture',
];

class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  String? _budget;
  String? _pace;
  final Set<String> _interests = {};
  Airport? _homeAirport;
  final _interestController = TextEditingController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(preferencesProvider.notifier).load();
      final prefs = ref.read(preferencesProvider).prefs;
      if (prefs != null && mounted) {
        setState(() {
          _budget = prefs.budget;
          _pace = prefs.pace;
          _interests.addAll(prefs.interests);
          final home = prefs.homeAirport;
          if (home != null && home.isNotEmpty) {
            _homeAirport = Airport(iataCode: home, name: home);
          }
          _initialized = true;
        });
      } else if (mounted) {
        setState(() => _initialized = true);
      }
    });
  }

  @override
  void dispose() {
    _interestController.dispose();
    super.dispose();
  }

  void _addInterest() {
    final t = _interestController.text.trim();
    if (t.isNotEmpty) {
      setState(() => _interests.add(t));
      _interestController.clear();
    }
  }

  Future<void> _save() async {
    final ok = await ref.read(preferencesProvider.notifier).save(
          budget: _budget,
          pace: _pace,
          interests: _interests.toList(),
          homeAirport: _homeAirport?.iataCode,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Preferences saved' : 'Could not save preferences')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(preferencesProvider);

    // Chips = suggested set plus any custom interests already selected.
    final chipLabels = {..._suggestedInterests, ..._interests}.toList();

    return Scaffold(
      appBar: const GradientAppBar(
        title: Text('Travel profile'),
      ),
      body: state.loading && !_initialized
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Budget', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _ChoiceRow(
                  options: _budgets,
                  selected: _budget,
                  onSelected: (v) => setState(() => _budget = v),
                ),
                const SizedBox(height: 24),
                Text('Pace', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                _ChoiceRow(
                  options: _paces,
                  selected: _pace,
                  onSelected: (v) => setState(() => _pace = v),
                ),
                const SizedBox(height: 24),
                Text('Interests', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: chipLabels.map((label) {
                    final selected = _interests.contains(label);
                    return FilterChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (sel) => setState(() {
                        if (sel) {
                          _interests.add(label);
                        } else {
                          _interests.remove(label);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _interestController,
                        decoration: const InputDecoration(hintText: 'Add an interest'),
                        onSubmitted: (_) => _addInterest(),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.add), onPressed: _addInterest),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Home airport', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Used as the default origin when planning flights.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                AirportField(
                  label: 'Home airport',
                  icon: Icons.home,
                  selected: _homeAirport,
                  onSelected: (a) => setState(() => _homeAirport = a),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: state.saving ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: state.saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ],
            ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _ChoiceRow({required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: options.map((o) {
        return ChoiceChip(
          label: Text(o),
          selected: selected == o,
          onSelected: (sel) => onSelected(sel ? o : null),
        );
      }).toList(),
    );
  }
}
