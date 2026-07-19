import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

import '../models/plan_message.dart';

/// Prepares a picked/dropped image for the chat: validates, downscales large
/// photos to Claude's effective resolution, and re-encodes.
///
/// Decoding uses the engine codec (`ui.instantiateImageCodec` — the browser's
/// native decoder on web, so a 12 MP photo never runs through a pure-Dart
/// decoder on the main thread), and scaling happens on a `PictureRecorder`
/// canvas from the already-decoded frame. NOTE: `ui.ImageDescriptor.width` /
/// `.height` throw `UnsupportedError` on web, so dimensions must come from
/// the decoded frame, not a descriptor probe. Only the *encoding* of the
/// small result uses `package:image`.
class ImageAttachmentPipeline {
  /// Longest-side target. Anthropic downsizes anything beyond ~1568px anyway,
  /// so pixels above this are pure upload/token waste.
  static const maxDimension = 1568;

  /// Sources above this are rejected outright rather than processed.
  static const maxSourceBytes = 10 * 1024 * 1024;

  /// Already-small images (dimension AND byte size) pass through untouched:
  /// screenshots keep PNG crispness, small GIFs keep their animation, and the
  /// common case re-encodes nothing.
  static const passThroughBytes = 500 * 1024;

  static const allowedMediaTypes = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  };

  const ImageAttachmentPipeline();

  /// Returns the processed attachment, or null when [bytes] is not a usable
  /// image (unsupported type, oversized source, undecodable data). Callers
  /// surface null as a "couldn't read that image" notice.
  Future<PlanAttachment?> process(Uint8List bytes, String mediaType) async {
    final normalized = mediaType.toLowerCase().split(';').first.trim();
    if (!allowedMediaTypes.contains(normalized)) return null;
    if (bytes.isEmpty || bytes.length > maxSourceBytes) return null;

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      final longest = width > height ? width : height;

      if (longest <= maxDimension && bytes.length <= passThroughBytes) {
        image.dispose();
        return PlanAttachment(bytes: bytes, mediaType: normalized);
      }

      final scale = longest > maxDimension ? maxDimension / longest : 1.0;
      final targetW = (width * scale).round().clamp(1, width);
      final targetH = (height * scale).round().clamp(1, height);

      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final scaled = await picture.toImage(targetW, targetH);
      picture.dispose();
      image.dispose();

      final raw = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
      scaled.dispose();
      if (raw == null) return null;

      // JPEG has no alpha channel: flatten transparency onto white before
      // encoding, or transparent PNG regions would come out garbage. JPEG
      // sources are opaque already — skip the extra composite pass.
      var decoded = img.Image.fromBytes(
        width: targetW,
        height: targetH,
        bytes: raw.buffer,
        numChannels: 4,
      );
      if (normalized != 'image/jpeg') {
        final canvas = img.Image(width: targetW, height: targetH);
        img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(canvas, decoded);
        decoded = canvas;
      }
      final encoded = img.encodeJpg(decoded, quality: 80);
      return PlanAttachment(
          bytes: Uint8List.fromList(encoded), mediaType: 'image/jpeg');
    } catch (e) {
      debugPrint('image_attachment_pipeline: $normalized rejected: $e');
      return null;
    }
  }
}
