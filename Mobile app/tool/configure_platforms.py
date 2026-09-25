#!/usr/bin/env python3
"""Idempotent permission/icon overlays on SDK-generated Android/iOS/web shells.
Only run in this newly created app, not against a different existing repository.
"""
from pathlib import Path
import json
import plistlib
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID_NS = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ANDROID_NS)
a = lambda name: '{' + ANDROID_NS + '}' + name

manifest_path = ROOT / 'android/app/src/main/AndroidManifest.xml'
if manifest_path.exists():
    tree = ET.parse(manifest_path)
    manifest = tree.getroot()
    existing = {node.get(a('name')) for node in manifest.findall('uses-permission')}
    # Online map tiles need INTERNET; map centering and report validation need
    # foreground location. image_picker delegates camera capture to Android's
    # camera app and needs no CAMERA or broad storage permission here.
    for permission in ['android.permission.INTERNET', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION']:
        if permission not in existing:
            manifest.insert(0, ET.Element('uses-permission', {a('name'): permission}))
    app = manifest.find('application')
    if app is None:
        raise SystemExit('Generated manifest has no application node.')
    app.set(a('label'), 'RoadGuard AI')
    app.set(a('allowBackup'), 'false')
    app.set(a('usesCleartextTraffic'), 'false')
    queries = manifest.find('queries')
    if queries is None:
        queries = ET.SubElement(manifest, 'queries')
    if not any(node.get(a('name')) == 'android.intent.action.TTS_SERVICE' for node in queries.iter('action')):
        intent = ET.SubElement(queries, 'intent')
        ET.SubElement(intent, 'action', {a('name'): 'android.intent.action.TTS_SERVICE'})
    ET.indent(tree, space='    ')
    tree.write(manifest_path, encoding='utf-8', xml_declaration=True)

for gradle in [ROOT / 'android/app/build.gradle.kts', ROOT / 'android/app/build.gradle']:
    if gradle.exists():
        text = gradle.read_text()
        text = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', text)
        text = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', text)
        gradle.write_text(text)

plist_path = ROOT / 'ios/Runner/Info.plist'
if plist_path.exists():
    with plist_path.open('rb') as handle:
        values = plistlib.load(handle)
    values.update({
        'CFBundleDisplayName': 'RoadGuard AI',
        'CFBundleName': 'RoadGuard AI',
        'NSLocationWhenInUseUsageDescription': 'Show your position when you choose My location on the map, and check your hazard location and stationary speed before a report. Location is used only while the relevant screen is open.',
        'NSCameraUsageDescription': 'Take a single road-hazard confirmation photo after safely stopping.',
        'NSPhotoLibraryUsageDescription': 'RoadGuard only reads image data you explicitly choose for a report.',
        'NSMotionUsageDescription': 'Road-sensor contribution requires separate consent and a verified account. It is not enabled in this guest build.',
        # Retained for geolocator_apple compatibility: this generated project uses
        # SwiftPM, with no Podfile or package-target Always bypass flag. The plugin
        # requests WhenInUse when that key exists. No UIBackgroundModes entry or
        # Always request is added. See docs/PERMISSIONS.md for the iOS release check.
        'NSLocationAlwaysAndWhenInUseUsageDescription': 'RoadGuard uses location only for the visible map after your request or the reporting screen. Background location and road sensing are not enabled.',
    })
    with plist_path.open('wb') as handle:
        plistlib.dump(values, handle, sort_keys=False)

podfile = ROOT / 'ios/Podfile'
if podfile.exists():
    text = podfile.read_text()
    if re.search(r"^\s*#?\s*platform :ios,", text, re.M):
        text = re.sub(r"^\s*#?\s*platform :ios,.*$", "platform :ios, '15.0'", text, flags=re.M)
    else:
        text = "platform :ios, '15.0'\n" + text
    podfile.write_text(text)
project = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
if project.exists():
    text = project.read_text()
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', text)
    project.write_text(text)

icons = ROOT / 'tool/platform_assets'
if icons.exists():
    for source in icons.rglob('*'):
        if source.is_file():
            target = ROOT / source.relative_to(icons)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

web_manifest = ROOT / 'web/manifest.json'
if web_manifest.exists():
    data = json.loads(web_manifest.read_text())
    data.update({'name': 'RoadGuard AI — Traveler preview', 'short_name': 'RoadGuard',
                 'description': 'Traveler app UI preview. Demo routes are not real navigation.',
                 'background_color': '#F5F7F3', 'theme_color': '#132F32'})
    web_manifest.write_text(json.dumps(data, indent=2) + '\n')
print('Configured native foreground permissions, branding, minimum platform targets and Android backup/cleartext settings.')
print('No background service, push entitlement, signing key or server credentials were added.')
