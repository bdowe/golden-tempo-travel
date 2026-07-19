import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:travel_route_planner/services/image_attachment_pipeline.dart';

/// The downscale pipeline (specs/chat-image-attachments). Also runnable with
/// `--platform chrome`, which matters: dart:ui image APIs differ on web
/// (ImageDescriptor dimension getters throw there — the reason the pipeline
/// reads dimensions from the decoded frame instead).
void main() {
  const pipeline = ImageAttachmentPipeline();

  Uint8List makePng(int w, int h) {
    final src = img.Image(width: w, height: h);
    img.fill(src, color: img.ColorRgb8(212, 0, 0));
    return Uint8List.fromList(img.encodePng(src));
  }

  test('oversized dimensions downscale to <=1568 and re-encode as JPEG',
      () async {
    final out = await pipeline.process(makePng(2000, 1500), 'image/png');
    expect(out, isNotNull);
    expect(out!.mediaType, 'image/jpeg');
    final decoded = img.decodeJpg(out.bytes!)!;
    expect(decoded.width, ImageAttachmentPipeline.maxDimension);
    expect(decoded.height, 1176); // aspect preserved (1500 * 1568/2000)
    // Solid red must survive the resize + alpha-flatten + JPEG round-trip.
    final px = decoded.getPixel(100, 100);
    expect(px.r, greaterThan(180));
    expect(px.g, lessThan(40));
  });

  test('small images pass through untouched (bytes and media type)', () async {
    final tinyPng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
    final out = await pipeline.process(tinyPng, 'image/png');
    expect(out, isNotNull);
    expect(out!.mediaType, 'image/png');
    expect(out.bytes, tinyPng);
  });

  test('mediaType parameters are normalized for the allowlist', () async {
    final tinyPng = makePng(2, 2);
    final out = await pipeline.process(tinyPng, 'Image/PNG; charset=binary');
    expect(out, isNotNull);
    expect(out!.mediaType, 'image/png');
  });

  test('unsupported types, empty and undecodable bytes reject to null',
      () async {
    expect(await pipeline.process(makePng(2, 2), 'application/pdf'), isNull);
    expect(await pipeline.process(Uint8List(0), 'image/png'), isNull);
    expect(
        await pipeline.process(
            Uint8List.fromList([1, 2, 3, 4]), 'image/png'),
        isNull);
  });

  test('sources over 10MB reject without decoding', () async {
    final huge = Uint8List(ImageAttachmentPipeline.maxSourceBytes + 1);
    expect(await pipeline.process(huge, 'image/png'), isNull);
  });
}
