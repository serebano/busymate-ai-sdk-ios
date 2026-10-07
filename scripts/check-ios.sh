#!/bin/bash
set -euo pipefail
python3 scripts/verify-release.py
swift package dump-package >/dev/null
xcodebuild -scheme BusymateAI -destination 'generic/platform=iOS Simulator' -derivedDataPath .build-derived build CODE_SIGNING_ALLOWED=NO
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
arch=$(uname -m)
xcrun swiftc -typecheck -target "${arch}-apple-ios15.0-simulator" -sdk "$sdk" -I .build-derived/Build/Products/Debug-iphonesimulator Examples/ChatViewController.swift
