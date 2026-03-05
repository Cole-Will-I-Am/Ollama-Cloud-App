#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/OllamaCloud.xcodeproj"

SCHEME="${SCHEME:-OllamaCloud}"
DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/OllamaCloud-DerivedData}"
BUNDLE_ID="${BUNDLE_ID:-com.colecantcode.ollamacloud}"
CONFIGURATION="${CONFIGURATION:-Debug}"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Project not found at: $PROJECT_PATH" >&2
  exit 1
fi

open -a Simulator

UDID="$(
  xcrun simctl list devices available | awk -F '[()]' -v name="$DEVICE_NAME" '
    $0 ~ name { print $2; exit }
  '
)"

if [[ -z "${UDID:-}" ]]; then
  echo "No available simulator found for: $DEVICE_NAME" >&2
  exit 1
fi

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "Building $SCHEME for $DEVICE_NAME..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build >/tmp/ollama_ios_build.log

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/OllamaCloud.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH" >&2
  echo "Build log: /tmp/ollama_ios_build.log" >&2
  exit 1
fi

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/tmp/ollama_ios_launch.log

if [[ -n "${SCREENSHOT_PATH:-}" ]]; then
  xcrun simctl io "$UDID" screenshot "$SCREENSHOT_PATH" >/dev/null
fi

echo "Launched $BUNDLE_ID"
echo "Device: $DEVICE_NAME ($UDID)"
echo "App: $APP_PATH"
echo "Build log: /tmp/ollama_ios_build.log"
