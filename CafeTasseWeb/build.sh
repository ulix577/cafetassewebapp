#!/bin/bash
# Builds the Wasm bundle. Usage: ./build.sh [debug|release]
#
# Build files go to ~/Library/Caches/CafeTasseWeb (override with CAFETASSE_BUILD_DIR), NOT into this
# folder: when the project lives in an iCloud-synced folder such as ~/Documents, iCloud creates
# "name 2.swift" conflict copies inside .build and the build breaks.
# The prefix maps keep the home directory path out of the .wasm (the output may be published).
set -euxo pipefail
cd "$(dirname "$0")"
BUILD_ROOT="${CAFETASSE_BUILD_DIR:-$HOME/Library/Caches/CafeTasseWeb}"
mkdir -p "$BUILD_ROOT"
swift package --build-system native --swift-sdk "${SWIFT_SDK_ID:-swift-6.4.2-RELEASE_wasm}" \
    -Xswiftc -file-prefix-map -Xswiftc "$HOME=/home" \
    -Xcc "-ffile-prefix-map=$HOME=/home" \
    --scratch-path "$BUILD_ROOT/build" \
    plugin --allow-writing-to-directory "$BUILD_ROOT/Package" \
    js --use-cdn -c "${1:-debug}" --output "$BUILD_ROOT/Package"
