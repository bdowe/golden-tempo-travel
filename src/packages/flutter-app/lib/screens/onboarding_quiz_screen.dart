import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/airport.dart';
import '../models/traveler_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import '../theme/spacing.dart';
import '../widgets/airport_field.dart';
import '../widgets/choice_chip_row.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/page_container.dart';

const _budgets = ['budget', 'mid', 'luxury'];
const _paces = ['relaxed', 'balanced', 'packed'];
const _suggestedInterests = [
  'museums', 'food', 'nightlife', 'nature', 'history', 'art', 'shopping', 'outdoors', 'beaches', 'architecture',
];
const _companionOptions = ['solo', 'partner', 'friends', 'family with kids', 'it varies'];
const _tripsMaxLength = 500;

/// Formats the quiz's free-form answers as profile-notes bullet lines, using
/// the same short-bullet convention the AI profile distiller maintains so the
/// two sources merge cleanly. Returns '' when there is nothing to note.
String buildOnboardingProfileNotes({String? companions, required String tripsInMind}) {
  final lines = <String>[];
  if (companions != null && companions.isNotEmpty) {
    lines.add('- Travels with: $companions');
  }
  final trips = tripsInMind.trim();
  if (trips.isNotEmpty) {
    lines.add('- Trips in mind: ${trips.replaceAll(RegExp(r'\s*\n+\s*'), '; ')}');
  }
  return lines.join('\n');
}

/// One-time signup quiz that seeds the traveler profile. Rendered by AuthGate
/// (instead of the app shell) while the signed-in user still owes onboarding —
/// completion/skip flips auth state, which swaps this screen out. Every
/// question is optional and Skip is always available; this screen must only be
/// shown to brand-new users (it replaces profile notes wholesale).
class OnboardingQuizScreen extends ConsumerStatefulWidget {
  /// When true the quiz was pushed as a profile "retake" (account menu)
  /// rather than shown by AuthGate at signup: finishing pops back instead of
  /// relying on AuthGate to swap the screen, and Skip just leaves.
  final bool retake;

  const OnboardingQuizScreen({super.key, this.retake = false});

  @override
  ConsumerState<OnboardingQuizScreen> createState() => _OnboardingQuizScreenState();
}

class _OnboardingQuizScreenState extends ConsumerState<OnboardingQuizScreen> {
  static const _stepCount = 5;

  final _pageController = PageController();
  int _step = 0;
  bool _submitting = false;
  bool _seededFromPrefs = false;

  String? _budget;
  String? _pace;
  final Set<String> _interests = {};
  String? _companions;

  @override
  void initState() {
    super.initState();
    // A retake edits the EXISTING profile: seed the form from saved
    // preferences so an untouched step keeps its values instead of wiping
    // them (save() sends interests as provided-including-empty).
    if (widget.retake) {
      final prefs = ref.read(preferencesProvider).prefs;
      if (prefs != null) {
        _seedFrom(prefs);
      } else {
        ref.read(preferencesProvider.notifier).load();
      }
    }
  }

  void _seedFrom(TravelerPreferences prefs) {
    _seededFromPrefs = true;
    _budget = prefs.budget;
    _pace = prefs.pace;
    _interests.addAll(prefs.interests);
    final home = prefs.homeAirport;
    if (home != null && home.isNotEmpty) {
      _homeAirport = Airport(iataCode: home, name: home);
    }
  }
  Airport? _homeAirport;
  final _interestController = TextEditingController();
  final _tripsController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    _interestController.dispose();
    _tripsController.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _addInterest() {
    final t = _interestController.text.trim();
    if (t.isNotEmpty) {
      setState(() => _interests.add(t));
      _interestController.clear();
    }
  }

  Future<void> _skip() async {
    if (widget.retake) {
      Navigator.of(context).pop();
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    await ref.read(authProvider.notifier).completeOnboarding();
    // No setState after: completing onboarding swaps this screen out via
    // AuthGate, and the local-unlock fallback means it always succeeds.
  }

  Future<void> _finish() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final notes = buildOnboardingProfileNotes(
      companions: _companions,
      tripsInMind: _tripsController.text,
    );
    final ok = await ref.read(preferencesProvider.notifier).save(
          budget: _budget,
          pace: _pace,
          interests: _interests.toList(),
          homeAirport: _homeAirport?.iataCode,
          // null keeps notes untouched (they're empty for a brand-new user).
          // A retake NEVER writes notes: the accumulated AI-distilled profile
          // must not be replaced by one or two quiz bullets.
          profileNotes: widget.retake || notes.isEmpty ? null : notes,
        );
    if (!ok) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your answers — try again, or skip for now.')),
      );
      return;
    }
    if (widget.retake) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Travel profile updated')),
      );
      return;
    }
    await ref.read(authProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    // Retake with preferences still loading at initState: seed once they land.
    if (widget.retake && !_seededFromPrefs) {
      ref.listen(preferencesProvider.select((s) => s.prefs), (prev, prefs) {
        if (prefs != null && !_seededFromPrefs) {
          setState(() => _seedFrom(prefs));
        }
      });
    }
    final theme = Theme.of(context);
    final isLast = _step == _stepCount - 1;

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('Set up your travel profile'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _skip,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: SafeArea(
        child: PageContainer(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStep(
                      title: 'What\'s your travel style?',
                      subtitle: 'Helps the planner match stays and activities to you.',
                      children: [
                        Text('Budget', style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        ChoiceChipRow(
                          options: _budgets,
                          selected: _budget,
                          onSelected: (v) => setState(() => _budget = v),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text('Pace', style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        ChoiceChipRow(
                          options: _paces,
                          selected: _pace,
                          onSelected: (v) => setState(() => _pace = v),
                        ),
                      ],
                    ),
                    _buildStep(
                      title: 'What do you love doing on a trip?',
                      subtitle: 'Pick as many as you like.',
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: {..._suggestedInterests, ..._interests}.map((label) {
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
                        const SizedBox(height: AppSpacing.sm),
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
                      ],
                    ),
                    _buildStep(
                      title: 'Who do you usually travel with?',
                      children: [
                        ChoiceChipRow(
                          options: _companionOptions,
                          selected: _companions,
                          onSelected: (v) => setState(() => _companions = v),
                        ),
                      ],
                    ),
                    _buildStep(
                      title: 'Where do you fly from?',
                      subtitle: 'Used as the default origin when planning flights.',
                      children: [
                        AirportField(
                          label: 'Home airport',
                          icon: Icons.home,
                          selected: _homeAirport,
                          onSelected: (a) => setState(() => _homeAirport = a),
                        ),
                      ],
                    ),
                    _buildStep(
                      title: 'Any trips you\'re dreaming about?',
                      subtitle: 'Places, seasons, occasions — the planner will keep them in mind.',
                      children: [
                        TextField(
                          controller: _tripsController,
                          maxLines: 4,
                          maxLength: _tripsMaxLength,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Japan for cherry blossom season, a Greek island hop next summer…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    if (_step > 0)
                      TextButton(
                        onPressed: _submitting ? null : () => _goTo(_step - 1),
                        child: const Text('Back'),
                      ),
                    const Spacer(),
                    _StepDots(count: _stepCount, current: _step),
                    const Spacer(),
                    FilledButton(
                      onPressed: _submitting
                          ? null
                          : () => isLast ? _finish() : _goTo(_step + 1),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isLast ? 'Finish' : 'Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: theme.textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        ...children,
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  final int count;
  final int current;

  const _StepDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == current ? scheme.primary : scheme.outlineVariant,
          ),
        );
      }),
    );
  }
}
