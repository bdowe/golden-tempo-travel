import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation of paste-from-clipboard image capture
/// (specs/chat-image-attachments): a document-level `paste` listener that
/// extracts image files (screenshot paste, copied image) and hands their
/// (bytes, mimeType) pairs to [onImages].
///
/// [isActive] gates handling — the caller passes a composer-has-focus check,
/// so a paste lands in exactly one chat panel even when several are mounted
/// (Agent tab behind the Trips tab's refine panel), and pasting into other
/// text fields elsewhere in the app is never intercepted.
///
/// Text-only pastes are left alone entirely: preventDefault fires only when
/// image files are present, so normal paste into the message field works
/// unchanged.
///
/// Returns a cancel function that removes the listener (call from dispose).
void Function() listenForPastedImages(
  bool Function() isActive,
  void Function(List<(Uint8List, String)> files) onImages,
) {
  final handler = ((web.Event e) {
    if (!isActive()) return;
    final data = (e as web.ClipboardEvent).clipboardData;
    if (data == null) return;
    final files = <web.File>[];
    for (var i = 0; i < data.items.length; i++) {
      final item = data.items[i];
      if (item.kind == 'file' && item.type.startsWith('image/')) {
        final file = item.getAsFile();
        if (file != null) files.add(file);
      }
    }
    if (files.isEmpty) return;
    e.preventDefault(); // keep the file from also pasting as text/filename
    Future.wait(files.map((f) async {
      final buffer = await f.arrayBuffer().toDart;
      return (buffer.toDart.asUint8List(), f.type);
    })).then(onImages);
  }).toJS;
  web.document.addEventListener('paste', handler);
  return () => web.document.removeEventListener('paste', handler);
}
