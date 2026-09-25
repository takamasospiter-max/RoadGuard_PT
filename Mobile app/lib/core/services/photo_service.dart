import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'permission_service.dart';

// Rebuild from pixel data, rather than copying an image object with its EXIF/IPTC/XMP.
// Orientation is applied before metadata is removed. This is defense in depth;
// the gateway MUST independently strip identity, device tokens and metadata (SRS p25).
Uint8List sanitizePhoto(Uint8List input) {
  if (input.length > 15 * 1024 * 1024) {
    throw const FormatException('Use a photo smaller than 15 MB.');
  }
  const invalidPhoto = FormatException(
    'Unsupported photo. Please capture a JPEG or PNG image.',
  );
  final isJpeg = input.length >= 2 && input[0] == 0xff && input[1] == 0xd8;
  final isPng =
      input.length >= 8 &&
      listEquals(input.sublist(0, 8), const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]);
  img.Image? decoded;
  try {
    // Avoid probing unrelated formats. Malformed camera bytes may make image
    // decoders throw RangeError or decoder-specific exceptions.
    decoded = isJpeg
        ? img.decodeJpg(input)
        : isPng
        ? img.decodePng(input)
        : null;
  } catch (_) {
    throw invalidPhoto;
  }
  if (decoded == null) throw invalidPhoto;
  if (decoded.width * decoded.height > 24000000) {
    throw const FormatException('Use a camera photo of 24 megapixels or less.');
  }
  final oriented = img.bakeOrientation(decoded);
  final rgb = oriented.getBytes(order: img.ChannelOrder.rgb);
  final clean = img.Image.fromBytes(
    width: oriented.width,
    height: oriented.height,
    bytes: rgb.buffer,
    bytesOffset: rgb.offsetInBytes,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(clean, quality: 90));
}

abstract interface class PhotoService {
  Future<Uint8List?> capture();
  Future<Uint8List?> recover();
}

class DevicePhotoService implements PhotoService {
  DevicePhotoService({PermissionService? permissions})
    : _permissions = permissions ?? const DevicePermissionService();

  final PermissionService _permissions;
  final ImagePicker _picker = ImagePicker();

  @override
  Future<Uint8List?> capture() async {
    switch (await _permissions.requestCamera()) {
      case PermissionState.granted:
        break;
      case PermissionState.permanentlyDenied:
        throw StateError(
          'Camera access is blocked. Open app settings to allow it.',
        );
      case PermissionState.restricted:
        throw StateError('Camera access is restricted on this device.');
      case PermissionState.unavailable:
        throw StateError('Camera is unavailable on this device.');
      case PermissionState.denied:
        throw StateError(
          'Camera access was not allowed. Grant camera access to attach report evidence.',
        );
      case PermissionState.unknown || PermissionState.requesting:
        throw StateError('Camera permission could not be confirmed.');
    }
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    return compute(sanitizePhoto, await image.readAsBytes());
  }

  @override
  Future<Uint8List?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    if (files == null || files.isEmpty) return null;
    return compute(sanitizePhoto, await files.first.readAsBytes());
  }
}
