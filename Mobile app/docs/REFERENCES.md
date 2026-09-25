# Implementation references

The attached RoadGuard_AI_SRS.pdf is the requirements baseline. These official maintainer references were consulted for implementation APIs and package compatibility. They do not resolve the SRS’s product-design ambiguities.

- Flutter SDK archive and stable release notes: https://docs.flutter.dev/install/archive and https://docs.flutter.dev/release/release-notes
- Riverpod 3 package and NotifierProvider API: https://pub.dev/packages/flutter_riverpod and https://pub.dev/documentation/flutter_riverpod/latest/flutter_riverpod/NotifierProvider-class.html
- go_router and ShellRoute: https://pub.dev/packages/go_router and https://pub.dev/documentation/go_router/latest/go_router/ShellRoute-class.html
- SharedPreferencesAsync and non-critical preference storage guidance: https://pub.dev/packages/shared_preferences
- Native SQLite support and transactions: https://pub.dev/packages/sqflite
- Geolocator permissions and location streams: https://pub.dev/packages/geolocator
- Camera capture, Android process-death recovery and iOS permission declarations: https://pub.dev/packages/image_picker
- Sensor platform requirements and sampling API: https://pub.dev/packages/sensors_plus
- Text-to-speech: https://pub.dev/packages/flutter_tts
- HTTP client injection/testing: https://pub.dev/packages/http
- Pixel-only image reconstruction: https://pub.dev/documentation/image/latest/image/Image/Image.fromBytes.html

Consulted 18 September 2026. Actual dependency resolution and native compilation remain unverified in this delivery environment.
