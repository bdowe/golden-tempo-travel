import 'package:flutter/material.dart';

/// Shows the app's standard plain-text snack bar — the one-liner every screen
/// used to spell out as `ScaffoldMessenger.of(context).showSnackBar(...)`.
/// Callers keep their own `mounted` checks after async gaps, exactly as they
/// did when the boilerplate lived inline.
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
