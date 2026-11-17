#!/bin/bash
# Builds the Wasm bundle into .build/plugins/PackageToJS/outputs/Package
# Usage: ./build.sh [debug|release]
# The prefix maps keep the home directory path out of the .wasm (the output may be published).
set -euxo pipefail
cd "$(dirname "$0")"
swift package --build-system native --swift-sdk "${SWIFT_SDK_ID:-swift-6.4.2-RELEASE_wasm}" \
    -Xswiftc -file-prefix-map -Xswiftc "$HOME=/home" \
    -Xcc "-ffile-prefix-map=$HOME=/home" \
    js --use-cdn -c "${1:-debug}"
