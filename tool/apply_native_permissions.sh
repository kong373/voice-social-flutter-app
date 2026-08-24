#!/usr/bin/env bash
set -euo pipefail

# Apply the app-owned iOS usage descriptions to a generated Flutter host.
# Android permissions are supplied by the first_party_native_permissions plugin
# manifest and are merged by Gradle; no provider or push permission is added.

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
IOS_PLIST="$ROOT_DIR/ios/Runner/Info.plist"

if [[ ! -f "$IOS_PLIST" ]]; then
  exit 0
fi

if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "PlistBuddy is required to add iOS permission usage descriptions." >&2
  exit 1
fi

set_plist_value() {
  local key="$1"
  local value="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$IOS_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$IOS_PLIST"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$IOS_PLIST"
  fi
}

set_plist_value \
  NSMicrophoneUsageDescription \
  '用于房间上麦发言和音频诊断。'
set_plist_value \
  NSPhotoLibraryUsageDescription \
  '用于选择头像、发布动态图片和提交举报凭证。'
