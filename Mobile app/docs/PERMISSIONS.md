# Map and device permissions

Reviewed on 21 September 2026 against the resolved `geolocator 14.0.3`,
`geolocator_apple 2.3.14`, `image_picker 1.2.3` and the existing native shells.
Online map browsing does not require GPS access. My location is an explicit
foreground action; it does not authorize background trip tracking or telemetry.

## Android

| Declaration | Purpose and request timing |
|---|---|
| `android.permission.INTERNET` | Download OpenStreetMap map tiles over HTTPS. Normal manifest permission; no runtime dialog. Already present in the main manifest, so release builds have network access too. |
| `android.permission.ACCESS_COARSE_LOCATION` | Let users choose approximate foreground location. Requested by the location action or the existing optional onboarding/report flow. Denial still permits map browsing. |
| `android.permission.ACCESS_FINE_LOCATION` | Offer precise map positioning and the existing report location/accuracy checks. A grant alone does not establish a safe, stationary report fix. |

All three declarations were already present; no duplicate or additional Android
permission was necessary. The app stops its map location subscription when
Explore is covered, left or backgrounded. Reporting owns separate GPS evidence
and still blocks unknown, stale, invalid, mocked or moving fixes.

The current photo adapter uses `image_picker` to launch the system camera. It
does not need an app-level `CAMERA` declaration, broad storage permissions or a
microphone grant. Android's camera application handles capture; the returned
photo is sanitized before the app stores it. This follows the package's
[Android setup and activity recovery documentation](https://pub.dev/packages/image_picker#android).

No `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION`, notification,
microphone or broad media/storage permission is added. This app does not start
a location foreground service or keep tracking after its activity is hidden.
Android distinguishes a visible activity's foreground location from a service
that continues with a persistent notification. See [Android location access](https://developer.android.com/develop/sensors-and-location/location/permissions).

## iOS

| Existing key | Current use |
|---|---|
| `NSLocationWhenInUseUsageDescription` | Updated to explain map positioning on request and report checks. This is the location authorization requested by the app. |
| `NSCameraUsageDescription` | Report photo capture after the stationary check. |
| `NSPhotoLibraryUsageDescription` | Retained for the image-picker integration. No automatic gallery scan or new gallery feature was added. |
| `NSMotionUsageDescription` | Existing description retained for the unconnected sensor adapter. Guest map use does not start motion collection. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Existing package-compatibility description retained and updated; it is not a new Always authorization request. |

The generated iOS project uses Swift Package Manager and has no `Podfile`.
The resolved `geolocator_apple` package's `Package.swift` does not define
`BYPASS_PERMISSION_LOCATION_ALWAYS`. The package documents a CocoaPods target
flag for omitting the Always description; adding an unused Podfile would not
configure the existing Swift package. No dependency-manager migration, package
cache patch or background location entitlement was introduced. The resolved
plugin's `PermissionHandler.m` chooses `requestWhenInUseAuthorization` when the
WhenInUse description exists; Always is only an alternate branch.

Before an iOS release, validate authorization on Xcode/a physical device and
review a supported package-target bypass configuration so the unused Always
description can be removed. iOS native validation has not been performed in this
Linux workspace. See [geolocator iOS setup](https://pub.dev/packages/geolocator#ios)
and [the publisher's Swift package manifest](https://github.com/Baseflow/flutter-geolocator/blob/main/geolocator_apple/darwin/geolocator_apple/Package.swift).

`image_picker` requires camera/photo-library purpose strings on iOS, with a
microphone description only for recording video. This app only captures still
photos. See [image_picker iOS setup](https://pub.dev/packages/image_picker#ios).

## Network and local data

Map tiles are a real third-party network integration, independent of RoadGuard
reports. The OpenStreetMap tile provider receives the requested tile area, IP
address and application identification. Centering the map on a GPS fix therefore
reveals that approximate area through tile requests. Reports, photos, account
details and a GPS track are not uploaded as map-request payloads.

Native map image caching is separate from SQLite reports and the telemetry
outbox. Cached tiles can indicate areas viewed and may remain after Clear local
data. Android users can clear the app cache in device settings. The cache
reduces repeat downloads; it is not a guaranteed offline map. See
[flutter_map caching](https://docs.fleaflet.dev/layers/tile-layer/caching) and
[OpenStreetMap tile usage policy](https://operations.osmfoundation.org/policies/tiles/).

The existing `tool/configure_platforms.py` overlay keeps the foreground
declarations and updated descriptions consistent when native shells are
generated. It does not request runtime authorization or grant consent.

Routes and hazard alerts remain samples. Map access does not connect account
authentication, live directions, server report submission, background sensing
or remote notifications.
