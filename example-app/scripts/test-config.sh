#!/bin/sh
set -eu
EXAMPLE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
swift test --package-path "$EXAMPLE_DIR" --scratch-path "$EXAMPLE_DIR/.configuration-build" --jobs 1
