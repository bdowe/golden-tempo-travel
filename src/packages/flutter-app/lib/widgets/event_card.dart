import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/event.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';

/// A single local event: name, when, venue/category, opening the ticket/info
/// page externally on tap. Styled to sit beside itinerary and booking rows.
class EventCard extends StatelessWidget {
  final Event event;

  const EventCard({super.key, required this.event});

  Future<void> _open() async {
    if (event.url.isEmpty) return;
    final uri = Uri.tryParse(event.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.toolEvents;
    final subtitle = [
      if (event.venue.isNotEmpty) event.venue,
      if (event.category.isNotEmpty) event.category,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: event.url.isEmpty ? null : _open,
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
                child: Icon(Icons.local_activity, size: 20, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.whenLabel,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: accent, fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (event.url.isNotEmpty)
                Icon(Icons.open_in_new,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
