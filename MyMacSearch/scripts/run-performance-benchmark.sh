#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$script_dir/.." && pwd)"

export MYMACSEARCH_RUN_MILLION_BENCHMARK=1
swift test \
  --package-path "$package_dir" \
  --configuration release \
  --filter IndexPerformanceTests.testMillionEntrySelectiveQueryWarmP95
