#!/bin/bash
set -euo pipefail
EXAMPLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RESULTS="$EXAMPLE_DIR/.runtime-results"
mkdir -p "$RESULTS"
if [[ -e "$RESULTS/runtime.xcresult" ]]; then
  echo 'Existing runtime.xcresult preserved. Move it before running again.' >&2
  exit 1
fi
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import sys,json; r=[x["identifier"] for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x.get("platform")=="iOS"]; print(r[-1] if r else "")')
DEVICE_TYPE=$(xcrun simctl list devicetypes -j | python3 -c 'import sys,json; d=[x["identifier"] for x in json.load(sys.stdin)["devicetypes"] if x.get("productFamily")=="iPhone"]; print(d[-1] if d else "")')
[[ -n "$RUNTIME" && -n "$DEVICE_TYPE" ]] || { echo 'An installed iOS runtime and iPhone device type are required.' >&2; exit 1; }
SIM_ID=$(xcrun simctl create "Busymate SDK runtime $$" "$DEVICE_TYPE" "$RUNTIME")
cleanup() { xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true; xcrun simctl delete "$SIM_ID"; }
trap cleanup EXIT
xcodebuild -version
xcodebuild -project "$EXAMPLE_DIR/BusymateSDKExample.xcodeproj" \
  -scheme BusymateSDKExample -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$EXAMPLE_DIR/.derived-data" -resultBundlePath "$RESULTS/runtime.xcresult" \
  -only-testing:BusymateSDKExampleUITests -parallel-testing-enabled NO \
  -jobs 1 CODE_SIGNING_ALLOWED=NO test
