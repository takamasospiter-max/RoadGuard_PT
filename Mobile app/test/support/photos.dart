import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A small real JPEG to stand in for a camera photo in tests
/// (a grey road with a dark pothole shape).
Uint8List testPhoto() {
  final image = img.Image(width: 320, height: 180);
  img.fill(image, color: img.ColorRgb8(120, 120, 120));
  img.fillCircle(
    image,
    x: 160,
    y: 100,
    radius: 30,
    color: img.ColorRgb8(30, 30, 30),
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
