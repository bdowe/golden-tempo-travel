import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/airport.dart';
import '../widgets/airport_field.dart';
import '../widgets/choice_chip_row.dart';
import '../widgets/gradient_app_bar.dart';
import '../l10n/l10n.dart';
import '../providers/preferences_provider.dart';
import '../utils/snack.dart';

// Canonical API values. These are sent to the server and read by the AI agent,
// so they are NEVER translated — only their display labels are
// (specs/i18n-spanish).
const _budgets = ['budget', 'mid', 'luxury'];
const _paces = ['relaxed', 'balanced', 'packed'];
const _suggestedInterests = [
  'museums', 'food', 'nightlife', 'nature', 'history', 'art', 'shopping', 'outdoors', 'beaches', 'architecture',
];

String _budgetLabel(AppLocalizations l10n, String value) => switch (value) {
      'budget' => l10n.prefsBudgetLow,
      'mid' => l10n.prefsBudgetMid,
      'luxury' => l10n.prefsBudgetLuxury,
      _ => value,
    };

String _paceLabel(AppLocalizations l10n, String value) => switch (value) {
      'relaxed' => l10n.prefsPaceRelaxed,
      'balanced' => l10n.prefsPaceBalanced,
      'packed' => l10n.prefsPacePacked,
      _ => value,
    };

/// Suggested interests get translated labels; anything the traveler typed
/// themselves is shown exactly as they wrote it.
String _interestLabel(AppLocalizations l10n, String value) => switch (value) {
      'museums' => l10n.prefsInterestMuseums,
      'food' => l10n.prefsInterestFood,
      'nightlife' => l10n.prefsInterestNightlife,
      'nature' => l10n.prefsInterestNature,
      'history' => l10n.prefsInterestHistory,
      'art' => l10n.prefsInterestArt,
      'shopping' => l10n.prefsInterestShopping,
      'outdoors' => l10n.prefsInterestOutdoors,
      'beaches' => l10n.prefsInterestBeaches,
      'architecture' => l10n.prefsInterestArchitecture,
      _ => value,
    };

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
  final _notesController = TextEditingController();
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
          _notesController.text = prefs.profileNotes ?? '';
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
    _notesController.dispose();
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
          // Always send the field's text: an emptied field clears the notes.
          profileNotes: _notesController.text.trim(),
        );
    if (!mounted) return;
    showSnack(context,
        ok ? context.l10n.prefsSaved : context.l10n.prefsSaveFailed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final state = ref.watch(preferencesProvider);

    // Chips = suggested set plus any custom interests already selected.
    final chipLabels = {..._suggestedInterests, ..._interests}.toList();

    return Scaffold(
      appBar: GradientAppBar(
        title: Text(l10n.prefsTitle),
      ),
      body: state.loading && !_initialized
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.prefsBudget, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ChoiceChipRow(
                  options: _budgets,
                  selected: _budget,
                  onSelected: (v) => setState(() => _budget = v),
                  labelBuilder: (v) => _budgetLabel(l10n, v),
                ),
                const SizedBox(height: 24),
                Text(l10n.prefsPace, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ChoiceChipRow(
                  options: _paces,
                  selected: _pace,
                  onSelected: (v) => setState(() => _pace = v),
                  labelBuilder: (v) => _paceLabel(l10n, v),
                ),
                const SizedBox(height: 24),
                Text(l10n.prefsInterests, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: chipLabels.map((label) {
                    final selected = _interests.contains(label);
                    return FilterChip(
                      label: Text(_interestLabel(l10n, label)),
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
                        decoration:
                            InputDecoration(hintText: l10n.prefsAddInterest),
                        onSubmitted: (_) => _addInterest(),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.add), onPressed: _addInterest),
                  ],
                ),
                const SizedBox(height: 24),
                Text(l10n.prefsHomeAirport, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  l10n.prefsHomeAirportHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                AirportField(
                  label: l10n.prefsHomeAirport,
                  icon: Icons.home,
                  selected: _homeAirport,
                  onSelected: (a) => setState(() => _homeAirport = a),
                ),
                const SizedBox(height: 24),
                Text(l10n.prefsProfileNotes,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  l10n.prefsProfileNotesHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    hintText: l10n.prefsProfileNotesHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: state.saving ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: state.saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.commonSave),
                ),
              ],
            ),
    );
  }
}
