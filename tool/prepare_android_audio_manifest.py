#!/usr/bin/env python3
"""Apply the app-level audio-only Agora permission overlay to a generated host.

The repository intentionally does not check in an Android host.  agora_rtc_engine
ships a broad library manifest, including video and phone-state permissions;
the generated application manifest is the higher-priority place to remove
those permissions for this audio-only product surface.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ANDROID_NAME = "http://schemas.android.com/apk/res/android"
TOOLS_NAME = "http://schemas.android.com/tools"
AGORA_COMPILE_SDK_VERSION = 36
AUDIO_FORBIDDEN_PERMISSIONS = (
    "android.permission.CAMERA",
    "android.permission.READ_PHONE_STATE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
)
AUDIO_FORBIDDEN_COMPONENTS = (
    "io.agora.rtc2.extensions.MediaProjectionMgr$LocalScreenCaptureAssistantActivity",
    "io.agora.rtc2.extensions.MediaProjectionMgr$LocalScreenSharingService",
)
AGORA_FORBIDDEN_JNI_LIBS = (
    "**/libagora_face_capture_extension.so",
    "**/libagora_lip_sync_extension.so",
)


def _patch_agora_compile_sdk(host: Path) -> None:
    """Expose the app compile SDK to Agora's legacy safeExtGet helper.

    agora_rtc_engine 6.6.3 still reads the root project's
    ``compileSdkVersion`` extra and falls back to 31 when it is absent.  The
    Flutter app itself already targets a current SDK, but the plugin's AAR
    metadata dependencies require that value to be visible from the root
    project as well.  Generated Flutter hosts have used both Kotlin DSL and
    Groovy root scripts, so keep this small patch compatible with either
    template.  Missing build files are allowed here because the manifest
    helper is also unit-tested in isolation.
    """

    android_dir = host / "android"
    candidates = (
        (android_dir / "build.gradle.kts", 'rootProject.extra["compileSdkVersion"] = '),
        (android_dir / "build.gradle", "compileSdkVersion = "),
    )
    for build_file, marker in candidates:
        if not build_file.is_file():
            continue
        build_text = build_file.read_text(encoding="utf-8")
        if marker in build_text:
            continue
        if build_file.suffix == ".kts":
            prefix = (
                f'rootProject.extra["compileSdkVersion"] = '
                f"{AGORA_COMPILE_SDK_VERSION}\n\n"
            )
        else:
            prefix = (
                "ext {\n"
                f"    compileSdkVersion = {AGORA_COMPILE_SDK_VERSION}\n"
                "}\n\n"
            )
        build_file.write_text(prefix + build_text, encoding="utf-8")


def _patch_agora_unique_package_names(host: Path) -> None:
    """Keep AGP 9 compatible with Agora's legacy duplicate AAR namespace.

    The official 6.6.3 Android dependency set contains the Iris wrapper and
    the RTC SDK AAR.  Both currently carry the historical ``io.agora.rtc``
    package in their manifests.  AGP 9 enables unique package-name validation
    by default, while AGP documents ``android.uniquePackageNames=false`` as
    the migration switch for libraries that have not migrated yet.  This does
    not remove either AAR or alter manifest merging; it only preserves the
    compatibility behavior required by the official dependency set.
    """

    properties = host / "android/gradle.properties"
    if not properties.is_file():
        return
    text = properties.read_text(encoding="utf-8")
    setting = "android.uniquePackageNames=false"
    setting_pattern = re.compile(r"(?m)^\s*android\.uniquePackageNames\s*=.*$")
    if setting_pattern.search(text) is not None:
        text = setting_pattern.sub(setting, text, count=1)
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += setting + "\n"
    properties.write_text(text, encoding="utf-8")


def _patch_agora_packaging_excludes(host: Path) -> None:
    """Drop Agora's optional face/lip extension JNI libraries from the host.

    The audio-only live path does not use the face-capture or lip-sync
    extensions, but the official Agora native bundle ships them inside the
    SDK AAR.  Keep the product APK lean by excluding only those two optional
    shared objects from the generated Android host.
    """

    android_app_dir = host / "android/app"
    candidates = (
        android_app_dir / "build.gradle.kts",
        android_app_dir / "build.gradle",
    )
    for build_file in candidates:
        if not build_file.is_file():
            continue
        text = build_file.read_text(encoding="utf-8")
        if all(forbidden in text for forbidden in AGORA_FORBIDDEN_JNI_LIBS):
            return
        if build_file.suffix == ".kts":
            block = (
                "\nandroid {\n"
                "    packaging {\n"
                "        jniLibs {\n"
                "            excludes += setOf(\n"
                '                "**/libagora_face_capture_extension.so",\n'
                '                "**/libagora_lip_sync_extension.so",\n'
                "            )\n"
                "        }\n"
                "    }\n"
                "}\n"
            )
        else:
            block = (
                "\nandroid {\n"
                "    packaging {\n"
                "        jniLibs {\n"
                "            excludes += [\n"
                '                "**/libagora_face_capture_extension.so",\n'
                '                "**/libagora_lip_sync_extension.so",\n'
                "            ]\n"
                "        }\n"
                "    }\n"
                "}\n"
            )
        if text and not text.endswith("\n"):
            text += "\n"
        build_file.write_text(text + block, encoding="utf-8")
        return


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: prepare_android_audio_manifest.py GENERATED_HOST", file=sys.stderr)
        return 2
    host = Path(sys.argv[1]).resolve()
    manifest = host / "android/app/src/main/AndroidManifest.xml"
    if not manifest.is_file():
        print(f"missing generated Android manifest: {manifest}", file=sys.stderr)
        return 2
    text = manifest.read_text(encoding="utf-8")
    manifest_match = re.search(r"<manifest\b[^>]*>", text)
    if manifest_match is None:
        print("generated Android manifest has no manifest element", file=sys.stderr)
        return 2
    opening = manifest_match.group(0)
    if "xmlns:tools=" not in opening:
        opening = opening[:-1] + f' xmlns:tools="{TOOLS_NAME}">'
        text = text[: manifest_match.start()] + opening + text[manifest_match.end() :]

    if "</manifest>" not in text:
        print("generated Android manifest has no closing manifest element", file=sys.stderr)
        return 2

    permission_lines = []
    if "android.permission.RECORD_AUDIO" not in text:
        permission_lines.append(
            '    <uses-permission android:name="android.permission.RECORD_AUDIO" />'
        )
    removal_lines = []
    for permission in AUDIO_FORBIDDEN_PERMISSIONS:
        if f'android:name="{permission}" tools:node="remove"' not in text:
            removal_lines.append(
                f'    <uses-permission android:name="{permission}" '
                'tools:node="remove" />'
            )
    if permission_lines or removal_lines:
        marker = "</manifest>"
        lines = permission_lines + removal_lines
        text = text.replace(marker, "\n" + "\n".join(lines) + "\n" + marker, 1)

    component_lines = []
    for component in AUDIO_FORBIDDEN_COMPONENTS:
        if f'android:name="{component}" tools:node="remove"' not in text:
            tag = "service" if component.endswith("Service") else "activity"
            component_lines.append(
                f'        <{tag} android:name="{component}" '
                'tools:node="remove" />'
            )
    if component_lines:
        if "</application>" in text:
            text = text.replace(
                "</application>",
                "\n" + "\n".join(component_lines) + "\n    </application>",
                1,
            )
        else:
            self_closing_application = re.search(
                r"<application\b[^>]*/>",
                text,
            )
            if self_closing_application is not None:
                opening = self_closing_application.group(0)[:-2] + ">"
                replacement = (
                    opening
                    + "\n"
                    + "\n".join(component_lines)
                    + "\n    </application>"
                )
                text = (
                    text[: self_closing_application.start()]
                    + replacement
                    + text[self_closing_application.end() :]
                )

    if 'android.permission.RECORD_AUDIO' not in text:
        print("audio-only host lost RECORD_AUDIO permission", file=sys.stderr)
        return 2
    if any(
        f'android:name="{component}" tools:node="remove"' not in text
        for component in AUDIO_FORBIDDEN_COMPONENTS
    ):
        print("audio-only host lost screen-capture removal markers", file=sys.stderr)
        return 2
    manifest.write_text(text, encoding="utf-8")
    _patch_agora_compile_sdk(host)
    _patch_agora_unique_package_names(host)
    _patch_agora_packaging_excludes(host)
    print(
        "android_audio_manifest=video,phone,screen-capture permissions/components "
        "removed; RECORD_AUDIO retained"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
