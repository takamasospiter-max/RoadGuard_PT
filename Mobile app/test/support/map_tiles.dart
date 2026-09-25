import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart' as image;

final _mapTileBytes = Uint8List.fromList(
  image.encodePng(
    image.Image(width: 1, height: 1)..setPixelRgba(0, 0, 233, 238, 228, 255),
  ),
);

/// Explicit tile source for offline tests. Production always uses network tiles.
TileProvider testMapTileProviderFactory() => TestMapTileProvider();

class TestMapTileProvider extends TileProvider {
  TestMapTileProvider({this.fail = false});

  bool fail;
  int requests = 0;
  bool disposed = false;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests++;
    return MemoryImage(fail ? Uint8List.fromList([1, 2, 3]) : _mapTileBytes);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
