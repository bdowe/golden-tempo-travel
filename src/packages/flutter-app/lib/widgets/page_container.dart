import 'package:flutter/material.dart';

/// Centers page content and caps its width on wide (web/desktop) layouts.
///
/// Place it *inside* the scroll view, around the content column, so the
/// scrollable region stays full-width while the content is constrained.
/// Currently used by the home screen; other scrollable screens (trips list,
/// preferences) can adopt it later.
class PageContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const PageContainer({super.key, required this.child, this.maxWidth = 700});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
