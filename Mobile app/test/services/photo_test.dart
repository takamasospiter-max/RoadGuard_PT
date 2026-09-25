import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:roadguard_ai/core/services/photo_service.dart';

void main() {
  test('metadata-like JPEG comments do not survive pixel re-encoding', () {
    final source = img.Image(width: 8, height: 5);
    final jpeg = img.encodeJpg(source);
    final marker = utf8.encode('GPS=private;Author=traveler;Device=phone');
    final length = marker.length + 2;
    final annotated = Uint8List.fromList([
      0xff,
      0xd8,
      0xff,
      0xfe,
      length >> 8,
      length & 0xff,
      ...marker,
      ...jpeg.skip(2),
    ]);
    final clean = sanitizePhoto(annotated);
    expect(latin1.decode(clean).contains('Author=traveler'), isFalse);
    expect(img.decodeImage(clean)?.width, 8);
    expect(img.decodeImage(clean)?.height, 5);
  });
  test('invalid image bytes are rejected', () {
    expect(
      () => sanitizePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
  test(
    'empty and truncated JPEG or PNG data has a friendly validation error',
    () {
      final source = img.Image(width: 8, height: 5);
      final samples = <List<int>>[
        [],
        [0xff, 0xd8],
        [0xff, 0xd8, 0xff, 0xe1, 0, 4],
        img.encodeJpg(source).take(24).toList(),
        img.encodePng(source).take(8).toList(),
        img.encodePng(source).take(24).toList(),
      ];
      for (final bytes in samples) {
        expect(
          () => sanitizePhoto(Uint8List.fromList(bytes)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Unsupported photo. Please capture a JPEG or PNG image.',
            ),
          ),
        );
      }
    },
  );
  test('valid PNG input is rebuilt as a JPEG', () {
    final clean = sanitizePhoto(img.encodePng(img.Image(width: 8, height: 5)));
    expect(clean.take(2), [0xff, 0xd8]);
    expect(img.decodeJpg(clean)?.width, 8);
    expect(img.decodeJpg(clean)?.height, 5);
  });
  test('other image formats are outside the camera JPEG and PNG contract', () {
    final bytes = img.encodeGif(img.Image(width: 8, height: 5));
    expect(() => sanitizePhoto(bytes), throwsFormatException);
  });
}
