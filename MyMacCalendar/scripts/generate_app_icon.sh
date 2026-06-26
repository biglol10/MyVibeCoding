#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/mymaccalendar-clang-cache"
export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/mymaccalendar-swift-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFT_MODULECACHE_PATH"
swift "$ROOT_DIR/scripts/generate_app_icon.swift"
