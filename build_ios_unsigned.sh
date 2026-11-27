#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build}"
PROJECT="$ROOT/MeloX.xcodeproj"
SCHEME="MeloX"
APP_NAME="MeloX"
DERIVED_DATA="$BUILD/DerivedData-iOS"
STAGING="$BUILD/IPA"
IPA_PATH="$BUILD/MeloX-Overtone-iOS-unsigned.ipa"
RELEASE_NOTES_PATH="$BUILD/ReleaseNotes.json"
RELEASE_NOTES_MARKDOWN_PATH="$BUILD/ReleaseNotes.md"
# Older CI callers used "legacy" for the unsigned build.
case "${MELOX_BUILD_BUNDLE_VARIANT:-personal}" in
  personal|legacy) ;;
  *) echo "Unsigned IPAs use the personal identity. For TestFlight use Tools/archive_testflight.py." >&2; exit 1 ;;
esac

EXPECTED_APP_BUNDLE_ID="com.aritxonly.MeloX"
EXPECTED_WIDGET_BUNDLE_ID="$EXPECTED_APP_BUNDLE_ID.LyricsWidget"
EXPECTED_WATCH_BUNDLE_ID="$EXPECTED_APP_BUNDLE_ID.watchkitapp"

rm -rf "$DERIVED_DATA" "$STAGING"
rm -f "$IPA_PATH" "$RELEASE_NOTES_PATH" "$RELEASE_NOTES_MARKDOWN_PATH"
mkdir -p "$BUILD"

echo "========== Build personal unsigned IPA / 构建个人版未签名 IPA =========="

xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  OVERTONE_BASE_BUNDLE_ID="$EXPECTED_APP_BUNDLE_ID" \
  OVERTONE_WIDGET_SUFFIX=LyricsWidget \
  REGISTER_APP_GROUPS=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER=""

APP_PATH="$(find "$DERIVED_DATA/Build/Products/Release-iphoneos" -maxdepth 2 -name "$APP_NAME.app" -type d -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "iOS build artifact not found / 找不到 iOS 构建产物：$APP_NAME.app"
  exit 1
fi

if [[ ! -f "$APP_PATH/ReleaseNotes.json" || ! -f "$APP_PATH/ReleaseNotes.md" ]]; then
  echo "Release-note metadata or Markdown is missing / 构建产物中缺少更新日志元数据或 Markdown"
  exit 1
fi

WIDGET_PATH="$APP_PATH/PlugIns/MeloXLyricsWidget.appex"
WATCH_PATH="$APP_PATH/Watch/MeloX Watch App.app"

assert_bundle_identifier() {
  local bundle_path="$1"
  local expected_bundle_id="$2"
  local product_name="$3"
  local actual_bundle_id

  if [[ ! -f "$bundle_path/Info.plist" ]]; then
    echo "$product_name Info.plist not found / 找不到 Info.plist：$bundle_path"
    exit 1
  fi

  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_path/Info.plist")"
  if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    echo "$product_name Bundle ID does not match the personal identity / Bundle ID 不符合构建要求"
    echo "Expected / 期望：$expected_bundle_id"
    echo "Actual / 实际：$actual_bundle_id"
    exit 1
  fi
}

assert_bundle_identifier "$APP_PATH" "$EXPECTED_APP_BUNDLE_ID" "MeloX"
assert_bundle_identifier "$WIDGET_PATH" "$EXPECTED_WIDGET_BUNDLE_ID" "MeloXLyricsWidget"
assert_bundle_identifier "$WATCH_PATH" "$EXPECTED_WATCH_BUNDLE_ID" "MeloX Watch App"

WATCH_COMPANION_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :WKCompanionAppBundleIdentifier' "$WATCH_PATH/Info.plist")"
if [[ "$WATCH_COMPANION_BUNDLE_ID" != "$EXPECTED_APP_BUNDLE_ID" ]]; then
  echo "Watch companion mismatch: $WATCH_COMPANION_BUNDLE_ID (expected $EXPECTED_APP_BUNDLE_ID)" >&2
  exit 1
fi

ditto --norsrc "$APP_PATH/ReleaseNotes.json" "$RELEASE_NOTES_PATH"
ditto --norsrc "$APP_PATH/ReleaseNotes.md" "$RELEASE_NOTES_MARKDOWN_PATH"

echo "========== Create unsigned IPA / 生成未签名 IPA =========="

mkdir -p "$STAGING/Payload"
ditto --norsrc "$APP_PATH" "$STAGING/Payload/$APP_NAME.app"
ditto -c -k --norsrc --keepParent "$STAGING/Payload" "$IPA_PATH"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "Failed to create unsigned IPA / 生成未签名 IPA 失败"
  exit 1
fi

unzip -tq "$IPA_PATH"
ls -lh "$IPA_PATH"

echo "Generated / 已生成：$IPA_PATH"
