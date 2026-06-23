import 'package:flutter/material.dart';

/// App bar painted with the app's teal gradient — the same
/// `teal.shade600 -> teal.shade900` used by the home "Plan Your Trip with AI"
/// banner. Use in place of [AppBar] so every screen shares one header look.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;

  /// Null inherits the app-wide AppBarTheme (centered); the home screen passes
  /// false so the brand mark sits on the left.
  final bool? centerTitle;

  const GradientAppBar(
      {super.key, required this.title, this.actions, this.centerTitle});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: actions,
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.teal.shade600, Colors.teal.shade900],
          ),
        ),
      ),
    );
  }
}
