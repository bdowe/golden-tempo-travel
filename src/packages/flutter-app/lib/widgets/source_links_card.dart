import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/source_link.dart';
import '../theme/spacing.dart';

/// A compact card listing external discovery links as tappable chips. Used where
/// there's no structured data to show — e.g. Greek events via more.com /
/// visitgreece.gr / Athens-Epidaurus.
class SourceLinksCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final List<SourceLink> links;

  const SourceLinksCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.links,
  });

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (links.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final link in links)
                  ActionChip(
                    avatar: Icon(Icons.open_in_new, size: 14, color: accent),
                    label: Text(link.label.isEmpty ? link.provider : link.label),
                    onPressed: () => _open(link.url),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
