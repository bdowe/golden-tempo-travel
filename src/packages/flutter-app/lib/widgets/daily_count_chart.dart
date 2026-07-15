import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/admin_insights.dart';
import '../theme/spacing.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// One small-multiple in the Trends tab: a single-series daily bar chart.
///
/// Follows the dashboard's dataviz conventions (see _ProviderClicks in
/// admin_metrics_screen.dart): one hue — the bars encode magnitude, the title
/// carries identity, so no legend or categorical palette. Labels wear text
/// tokens, never the series color; only the peak and latest values are
/// direct-labeled. Tap or drag across the bars to inspect a day (the caption
/// below is the touch equivalent of a hover tooltip).
///
/// [data] must be dense — one entry per day, zero-filled — which is what
/// [AdminTimeseries.denseSeries] returns.
class DailyCountChart extends StatefulWidget {
  final String title;
  final List<DailyCount> data;

  const DailyCountChart({super.key, required this.title, required this.data});

  @override
  State<DailyCountChart> createState() => _DailyCountChartState();
}

class _DailyCountChartState extends State<DailyCountChart> {
  int? _selected;

  int get _total => widget.data.fold(0, (sum, c) => sum + c.n);

  void _select(Offset localPos, double width) {
    if (widget.data.isEmpty || width <= 0) return;
    final slot = width / widget.data.length;
    final i = (localPos.dx / slot).floor().clamp(0, widget.data.length - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final selected =
        (_selected != null && _selected! < data.length) ? data[_selected!] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title, style: theme.textTheme.labelLarge),
            ),
            // Window total as a headline — text tokens, never the bar hue.
            Text('$_total', style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            onTapDown: (d) => _select(d.localPosition, constraints.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _select(d.localPosition, constraints.maxWidth),
            child: CustomPaint(
              size: Size(constraints.maxWidth, 84),
              painter: _DailyBarsPainter(
                data: data,
                selected: _selected,
                barColor: theme.colorScheme.primary,
                gridColor: theme.colorScheme.outlineVariant,
                labelStyle: captionStyle,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            if (data.isNotEmpty)
              Text(_fmtDay(data.first.day), style: captionStyle),
            const Spacer(),
            // The inspect caption — the touch stand-in for a hover tooltip.
            if (selected != null)
              Text('${_fmtDay(selected.day)} · ${selected.n}',
                  style: captionStyle?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  )),
            const Spacer(),
            if (data.length > 1)
              Text(_fmtDay(data.last.day), style: captionStyle),
          ],
        ),
      ],
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  final List<DailyCount> data;
  final int? selected;
  final Color barColor;
  final Color gridColor;
  final TextStyle? labelStyle;

  _DailyBarsPainter({
    required this.data,
    required this.selected,
    required this.barColor,
    required this.gridColor,
    required this.labelStyle,
  });

  static const _labelBand = 16.0; // reserved above the bars for direct labels

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final baseline = size.height - 1;
    final plotHeight = baseline - _labelBand;

    // Hairline baseline (recessive, solid).
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), grid);

    final maxN = data.fold(0, (m, c) => math.max(m, c.n));
    if (maxN == 0) return;

    // One gridline at the max of the scale; the peak's direct label carries
    // its value, so the line is unlabeled.
    canvas.drawLine(
        Offset(0, _labelBand), Offset(size.width, _labelBand), grid);

    // Slot geometry: 2px surface gaps between bars, collapsing when slots get
    // narrower than 4px (90-day windows on phones); bars capped at 24px.
    final slot = size.width / data.length;
    final gap = slot >= 4 ? 2.0 : (slot >= 2 ? 1.0 : 0.0);
    final barWidth = math.min(24.0, math.max(1.0, slot - gap));

    final paint = Paint()..color = barColor;
    final dimmed = Paint()..color = barColor.withValues(alpha: 0.45);
    int peak = 0;
    for (var i = 1; i < data.length; i++) {
      if (data[i].n > data[peak].n) peak = i;
    }

    for (var i = 0; i < data.length; i++) {
      final n = data[i].n;
      if (n == 0) continue;
      final h = plotHeight * n / maxN;
      final left = i * slot + (slot - barWidth) / 2;
      final topRadius = Radius.circular(math.min(4.0, barWidth / 2));
      // Rounded data-end, square at the baseline. Selection dims the other
      // bars rather than recoloring the selected one — color never changes
      // meaning, only emphasis.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, baseline - h, barWidth, h),
          topLeft: topRadius,
          topRight: topRadius,
        ),
        selected != null && selected != i ? dimmed : paint,
      );
    }

    // Selective direct labels: the peak, and the latest non-zero day (they
    // may coincide, and the latest yields when the two would collide).
    // Everything else is the tap caption's job.
    final peakRect = _label(canvas, size, slot, peak);
    final latest = data.length - 1;
    if (latest != peak && data[latest].n > 0) {
      _label(canvas, size, slot, latest, avoid: peakRect);
    }
  }

  /// Paints the value label for bar [i] centered above it (clamped to the
  /// canvas) and returns its rect. Skipped — returning null — when it would
  /// collide with [avoid].
  Rect? _label(Canvas canvas, Size size, double slot, int i, {Rect? avoid}) {
    final tp = TextPainter(
      text: TextSpan(text: '${data[i].n}', style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = i * slot + slot / 2;
    final dx = (center - tp.width / 2).clamp(0.0, size.width - tp.width);
    final rect = Rect.fromLTWH(dx, 0, tp.width, tp.height);
    if (avoid != null && rect.inflate(4).overlaps(avoid)) return null;
    tp.paint(canvas, rect.topLeft);
    return rect;
  }

  @override
  bool shouldRepaint(_DailyBarsPainter old) =>
      old.data != data ||
      old.selected != selected ||
      old.barColor != barColor ||
      old.gridColor != gridColor;
}
