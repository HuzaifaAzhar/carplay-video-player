"""Writes an AltStore-format source (apps.json) for TrollApps / AltStore / SideStore.

Usage: make_source.py <out_dir> <ipa_path> <version> <build> <base_url> <changelog_file>
"""
import datetime
import json
import os
import sys

out_dir, ipa_path, version, build, base_url, changelog_file = sys.argv[1:7]
base_url = base_url.rstrip("/")
size = os.path.getsize(ipa_path)
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(changelog_file, encoding="utf-8") as f:
    changelog = f.read().strip() or f"Build {build}"

shots_dir = os.path.join(out_dir, "screenshots")
screenshots = sorted(
    name for name in os.listdir(shots_dir) if name.lower().endswith((".png", ".jpg", ".jpeg"))
) if os.path.isdir(shots_dir) else []
screenshot_urls = [f"{base_url}/screenshots/{name}" for name in screenshots]

download_url = f"{base_url}/CarVideo.ipa"
description = (
    "Watch your own videos and YouTube on the CarPlay screen. Add videos from Files, Photos or a link, "
    "browse them in a grid sized for your car's screen, and control playback by touch, steering-wheel "
    "buttons or the iPhone. YouTube runs full screen on the car with an on-screen keyboard. Video is hidden "
    "while the car is moving (can be turned off). Needs TrollStore: the car screen uses a private entitlement."
)

app = {
    "name": "Car Video",
    "bundleIdentifier": "com.huzaifa.carvideo",
    "developerName": "Huzaifa Azhar",
    "subtitle": "Videos and YouTube on CarPlay",
    "localizedDescription": description,
    "iconURL": f"{base_url}/icon.png",
    "tintColor": "#FF7A1F",
    "category": "entertainment",
    "screenshots": screenshot_urls,
    "screenshotURLs": screenshot_urls,
    "versions": [
        {
            "version": version,
            "buildVersion": build,
            "date": date,
            "localizedDescription": changelog,
            "downloadURL": download_url,
            "size": size,
            "minOSVersion": "17.0",
        }
    ],
    # Legacy single-version fields for older AltStore / TrollApps clients.
    "version": version,
    "versionDate": date,
    "versionDescription": changelog,
    "downloadURL": download_url,
    "size": size,
    "appPermissions": {
        "entitlements": [
            "SBStarkCapable",
            "com.apple.runningboard.assertions.webkit",
            "com.apple.multitasking.systemappassertions",
        ],
        "privacy": {
            "NSLocationWhenInUseUsageDescription": "Used only while CarPlay is connected, to hide video on the car screen when the car is moving.",
        },
    },
}

source = {
    "name": "Car Video",
    "identifier": "com.huzaifa.carvideo.source",
    "subtitle": "Videos and YouTube on CarPlay",
    "description": description,
    "iconURL": f"{base_url}/icon.png",
    "website": base_url,
    "tintColor": "#FF7A1F",
    "apps": [app],
    "news": [],
}

with open(os.path.join(out_dir, "apps.json"), "w", encoding="utf-8") as f:
    json.dump(source, f, indent=2, ensure_ascii=False)
print(f"apps.json: Car Video {version} ({build}), {size} bytes, {len(screenshot_urls)} screenshots")
