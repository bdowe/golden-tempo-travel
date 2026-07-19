import 'dart:typed_data';

/// Non-web stub for paste-from-clipboard image capture: native desktop/mobile
/// clipboards need a plugin (super_clipboard-class dependency) that isn't
/// worth the weight while web is the primary target — pasting there is a
/// no-op and the paperclip/drag-drop paths cover image intake.
///
/// Returns a cancel function; see clipboard_images_web.dart for the real
/// implementation and the contract.
void Function() listenForPastedImages(
  bool Function() isActive,
  void Function(List<(Uint8List, String)> files) onImages,
) {
  return () {};
}
