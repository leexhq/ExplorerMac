#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$SOURCE_DIR/.build"
swiftc -swift-version 5 -module-cache-path "$SOURCE_DIR/.build/ModuleCache" "$SOURCE_DIR/Sources/FileCore.swift" "$SOURCE_DIR/Tests/FileCoreTests.swift" -o "$SOURCE_DIR/.build/FileCoreTests" -framework AppKit -framework UniformTypeIdentifiers
"$SOURCE_DIR/.build/FileCoreTests" "$SOURCE_DIR/.build"
