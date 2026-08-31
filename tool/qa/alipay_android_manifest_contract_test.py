#!/usr/bin/env python3
"""Check the minimal Alipay plugin and generated-host merged manifests.

The plugin declares only INTERNET. The official Alipay AAR contributes its
own non-exported H5 activities and the two exported result activities. A
generated Android host must be checked after Gradle merging; pass its merged
manifest with ``--merged-manifest`` to perform that second check.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PLUGIN_MANIFEST = ROOT / "packages/alipay_app_pay/android/src/main/AndroidManifest.xml"
ANDROID_NS = "http://schemas.android.com/apk/res/android"
NAME = f"{{{ANDROID_NS}}}name"
EXPORTED = f"{{{ANDROID_NS}}}exported"

EXPECTED_ACTIVITIES = {
    "com.alipay.sdk.app.H5PayActivity": "false",
    "com.alipay.sdk.app.H5AuthActivity": "false",
    "com.alipay.sdk.app.H5OpenAuthActivity": "false",
    "com.alipay.sdk.app.APayEntranceActivity": "false",
    "com.alipay.sdk.app.PayResultActivity": "true",
    "com.alipay.sdk.app.AlipayResultActivity": "true",
}

# These permissions belong to the generated host's already-reviewed audio,
# notification, Flutter engine, and AndroidX components. The Alipay plugin
# itself is intentionally limited to INTERNET; an unexpected permission in a
# merged host is treated as a dependency-scope regression.
KNOWN_HOST_PERMISSIONS = {
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_WIFI_STATE",
    "android.permission.BLUETOOTH",
    "android.permission.BLUETOOTH_CONNECT",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.FOREGROUND_SERVICE",
}


def fail(message: str) -> None:
    raise AssertionError(message)


def permission_names(root: ET.Element) -> list[str]:
    return [
        permission.attrib.get(NAME, "")
        for permission in root.findall("uses-permission")
    ]


def activities(root: ET.Element) -> dict[str, str | None]:
    application = root.find("application")
    if application is None:
        return {}
    return {
        activity.attrib.get(NAME, ""): activity.attrib.get(EXPORTED)
        for activity in application.findall("activity")
    }


def check_plugin_manifest() -> None:
    root = ET.parse(PLUGIN_MANIFEST).getroot()
    if permission_names(root) != ["android.permission.INTERNET"]:
        fail("plugin must declare only android.permission.INTERNET")
    if root.find("application") is not None:
        fail("plugin manifest must not contribute an application")


def check_merged_manifest(path: Path) -> None:
    root = ET.parse(path).getroot()
    permissions = permission_names(root)
    unexpected = {
        permission
        for permission in permissions
        if permission not in KNOWN_HOST_PERMISSIONS
        and not permission.endswith(".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")
    }
    if unexpected:
        fail(f"merged manifest has out-of-scope permissions: {sorted(unexpected)}")
    if "android.permission.QUERY_ALL_PACKAGES" in permissions:
        fail("merged manifest must not request QUERY_ALL_PACKAGES")
    if "android.permission.INTERNET" not in permissions:
        fail("merged manifest must retain INTERNET")

    merged_activities = activities(root)
    for name, expected_exported in EXPECTED_ACTIVITIES.items():
        if name not in merged_activities:
            fail(f"merged manifest missing official Alipay activity: {name}")
        if merged_activities[name] != expected_exported:
            fail(
                f"{name} exported={merged_activities[name]!r}, "
                f"expected {expected_exported!r}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--merged-manifest", type=Path)
    args = parser.parse_args()
    check_plugin_manifest()
    if args.merged_manifest is not None:
        check_merged_manifest(args.merged_manifest)
        print(f"Alipay plugin + merged manifest contract: PASS ({args.merged_manifest})")
    else:
        print("Alipay plugin manifest contract: PASS (merged manifest not supplied)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, ET.ParseError, OSError) as error:
        print(f"Alipay Android manifest contract: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
