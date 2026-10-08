#!/bin/bash
set -euo pipefail
EXAMPLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RESULTS="$EXAMPLE_DIR/.runtime-results"
mkdir -p "$RESULTS"
if [[ -e "$RESULTS/runtime.xcresult" ]]; then
  echo 'Existing runtime.xcresult preserved. Move it before running again.' >&2
  exit 1
fi
# Select the model/runtime pair of an available existing iPhone; the global
# device-type list also contains models incompatible with an installed runtime.
read -r RUNTIME DEVICE_TYPE < <(xcrun simctl list devices available -j | python3 -c 'import sys,json; pairs=[(runtime,d["deviceTypeIdentifier"]) for runtime,devices in json.load(sys.stdin)["devices"].items() for d in devices if d.get("isAvailable") and "iPhone" in d.get("deviceTypeIdentifier", "")]; print(" ".join(pairs[-1]) if pairs else "")')
[[ -n "$RUNTIME" && -n "$DEVICE_TYPE" ]] || { echo 'An available iPhone simulator and installed runtime are required.' >&2; exit 1; }
SIM_ID=$(xcrun simctl create "Busymate SDK runtime $$" "$DEVICE_TYPE" "$RUNTIME")
cleanup() { xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true; xcrun simctl delete "$SIM_ID"; }
trap cleanup EXIT
xcodebuild -version
xcodebuild -project "$EXAMPLE_DIR/BusymateSDKExample.xcodeproj" \
  -scheme BusymateSDKExample -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$EXAMPLE_DIR/.derived-data" -resultBundlePath "$RESULTS/runtime.xcresult" \
  -only-testing:BusymateSDKExampleUITests -parallel-testing-enabled NO \
  -jobs 1 CODE_SIGNING_ALLOWED=NO test
