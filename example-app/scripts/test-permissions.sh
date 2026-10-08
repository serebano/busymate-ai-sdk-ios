#!/bin/bash
set -euo pipefail
EXAMPLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ROOT=$(CDPATH= cd -- "$EXAMPLE_DIR/.." && pwd)
RESULTS="$EXAMPLE_DIR/.permission-results"
[[ ! -e "$RESULTS" ]] || { echo 'Existing permission evidence preserved; move it before another run.' >&2; exit 1; }
# Fail before creating/building any simulator unless the owner's exact live
# revision and build are supplied. Never grant permission through simctl.
python3 "$ROOT/scripts/assert-hosted-release.py" "$RESULTS/hosted-before.json"
read -r RUNTIME DEVICE_TYPE < <(xcrun simctl list devices available -j | python3 -c 'import sys,json; pairs=[(r,d["deviceTypeIdentifier"]) for r,ds in json.load(sys.stdin)["devices"].items() for d in ds if d.get("isAvailable") and "iPhone" in d.get("deviceTypeIdentifier", "")]; print(" ".join(pairs[-1]) if pairs else "")')
[[ -n "$RUNTIME" && -n "$DEVICE_TYPE" ]] || { echo 'An installed iPhone simulator runtime is required.' >&2; exit 1; }
SIM_ID=$(xcrun simctl create "Busymate permission acceptance $$" "$DEVICE_TYPE" "$RUNTIME")
cleanup() { xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true; xcrun simctl delete "$SIM_ID"; }
trap cleanup EXIT
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b
xcodebuild -version > "$RESULTS/xcode-version.txt"
BUILD_ARGS=(-project "$EXAMPLE_DIR/BusymateSDKExample.xcodeproj" -scheme BusymateSDKExample
  -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath "$EXAMPLE_DIR/.derived-data"
  -parallel-testing-enabled NO -jobs 1 CODE_SIGNING_ALLOWED=NO)
xcodebuild "${BUILD_ARGS[@]}" build-for-testing > "$RESULTS/build.log" 2>&1
xcrun simctl install "$SIM_ID" "$EXAMPLE_DIR/.derived-data/Build/Products/Debug-iphonesimulator/BusymateSDKExample.app"
for CASE in DictationGrant DictationDeny VoiceGrant VoiceDeny; do
  CASE_DIR="$RESULTS/$CASE"
  python3 "$ROOT/scripts/assert-hosted-release.py" "$CASE_DIR/hosted-before.json"
  # The app is owned by this fresh simulator; reset only its microphone state.
  xcrun simctl privacy "$SIM_ID" reset microphone ai.busymate.sdk.example
  TEST_STATUS=0
  TEST_RUNNER_BUSYMATE_PERMISSION_SUITE=1 xcodebuild "${BUILD_ARGS[@]}" \
    -resultBundlePath "$CASE_DIR/result.xcresult" \
    -only-testing:"BusymateSDKExampleUITests/FirstTapPermissionUITests/test$CASE" \
    test-without-building > "$CASE_DIR/test.log" 2>&1 || TEST_STATUS=$?
  if [[ -d "$CASE_DIR/result.xcresult" ]]; then
    xcrun xcresulttool export attachments --path "$CASE_DIR/result.xcresult" --output-path "$CASE_DIR/screenshots"
    xcrun xcresulttool get test-results summary --path "$CASE_DIR/result.xcresult" > "$CASE_DIR/summary.json"
  fi
  [[ "$TEST_STATUS" -eq 0 ]] || { cat "$CASE_DIR/test.log" >&2; exit "$TEST_STATUS"; }
  python3 - "$CASE_DIR/summary.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
if not (d.get('totalTestCount') == 1 and d.get('passedTests') == 1 and
        d.get('failedTests') == 0 and d.get('skippedTests') == 0):
    raise SystemExit(f'Expected exactly one passed, non-skipped permission case: {d}')
PY
  python3 "$ROOT/scripts/assert-hosted-release.py" "$CASE_DIR/hosted-after.json"
done
python3 "$ROOT/scripts/assert-hosted-release.py" "$RESULTS/hosted-after.json"
