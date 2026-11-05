#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
swift test --disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache"
node --test ChromeExtension/tests/*.test.js
