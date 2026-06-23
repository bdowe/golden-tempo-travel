import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ferry_option.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

/// A ferry option: route, date, and (when available) operator/time/price,
/// opening the Ferryhopper booking page on tap. In v1 link mode it renders as a
/// "Find ferries" CTA for the route.
class FerryCard extends StatelessWidget {
  final FerryOption option;

  const FerryCard({super.key, required this.option});

  Future<void> _open() async {
    if (option.bookingUrl.isEmpty) return;
    final uri = Uri.tryParse(option.bookingUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.toolFerries;
    // Structured detail line (filled once a real ferry API replaces link mode).
    final detail = [
      if (option.operator.isNotEmpty) option.operator,
      if (option.departTime.isNotEmpty) option.departTime,
      if (option.price > 0)
        '${option.currency.isEmpty ? '' : '${option.currency} '}${option.price.toStringAsFixed(0)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: option.bookingUrl.isEmpty ? null : _open,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.directions_boat, size: 20, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.routeLabel,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail.isNotEmpty
                          ? detail
                          : (option.date.isNotEmpty
                              ? 'Find ferries · ${option.date}'
                              : 'Find ferries on Ferryhopper'),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: accent, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (option.bookingUrl.isNotEmpty)
                Icon(Icons.open_in_new,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
