#!/bin/sh
set -eu
EXAMPLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
xcodebuild -project "$EXAMPLE_DIR/BusymateSDKExample.xcodeproj" -scheme BusymateSDKExample -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$EXAMPLE_DIR/.derived-data" -jobs 1 CODE_SIGNING_ALLOWED=NO build
