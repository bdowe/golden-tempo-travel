import 'package:flutter/material.dart';

/// Coarse relative-time label for cache staleness: "just now",
/// "5 minutes ago", "2 hours ago", "3 days ago". [now] is injectable for
/// tests; precision is deliberately low — travelers need "how stale", not a
/// timestamp.
String relativeTime(DateTime savedAt, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(savedAt);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) {
    return d.inMinutes == 1 ? '1 minute ago' : '${d.inMinutes} minutes ago';
  }
  if (d.inDays < 1) {
    return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  }
  return d.inDays == 1 ? '1 day ago' : '${d.inDays} days ago';
}

/// Pinned notice shown while a screen serves a cached (read-only) copy of
/// trip data because the network is unreachable. Says when the copy was
/// saved and offers a retry of the live fetch.
class OfflineBanner extends StatelessWidget {
  final DateTime savedAt;
  final VoidCallback onRetry;

  const OfflineBanner({super.key, required this.savedAt, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Offline — showing saved copy from ${relativeTime(savedAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onTertiaryContainer,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
