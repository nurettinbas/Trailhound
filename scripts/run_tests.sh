#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
RESULT_BUNDLE="${RESULT_BUNDLE:-build/TestResults.xcresult}"
INCLUDE_UI_TESTS="${INCLUDE_UI_TESTS:-1}"
ONLY_UI_TESTS="${ONLY_UI_TESTS:-0}"

mkdir -p build
rm -rf "$RESULT_BUNDLE"

TEST_ARGS=()
if [[ "$ONLY_UI_TESTS" == "1" ]]; then
  TEST_ARGS+=(-only-testing:TrailhoundUITests)
elif [[ "$INCLUDE_UI_TESTS" == "0" ]]; then
  TEST_ARGS+=(-only-testing:TrailhoundTests)
fi

XCODEBUILD_SETTINGS=()
if [[ "${CI:-}" == "true" ]]; then
  XCODEBUILD_SETTINGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
fi

RETRY_ARGS=()
if [[ "${CI:-}" == "true" ]]; then
  RETRY_ARGS+=(-retry-tests-on-failure)
fi

boot_simulator_if_needed() {
  local sim_id=""
  if [[ "$DESTINATION" == *"id="* ]]; then
    sim_id="${DESTINATION##*id=}"
  fi
  if [[ -n "$sim_id" ]]; then
    echo "Booting simulator ${sim_id}"
    xcrun simctl boot "$sim_id" 2>/dev/null || true
  fi
}

print_failure_summary() {
  [[ -d "$RESULT_BUNDLE" ]] || return 0
  if ! command -v xcrun >/dev/null 2>&1; then
    return 0
  fi

  echo ""
  echo "=== Test failure summary ==="
  xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" 2>/dev/null || true

  echo ""
  echo "=== Failed tests ==="
  xcrun xcresulttool get test-results tests --path "$RESULT_BUNDLE" 2>/dev/null \
    | python3 - <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

def walk(node):
    if isinstance(node, dict):
        status = node.get("testStatus", {})
        if status.get("status") == "Failure":
            name = node.get("name") or node.get("identifier")
            if name:
                print(name)
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)

walk(data)
PY
}

boot_simulator_if_needed

# Bash 3.2 + `set -u` treats empty "${arr[@]}" as unbound; build one argv list instead.
XCODEBUILD_ARGV=(
  test
  -project Trailhound.xcodeproj
  -scheme Trailhound
  -destination "$DESTINATION"
  -resultBundlePath "$RESULT_BUNDLE"
  -parallel-testing-enabled NO
)
if ((${#RETRY_ARGS[@]})); then
  XCODEBUILD_ARGV+=("${RETRY_ARGS[@]}")
fi
if ((${#XCODEBUILD_SETTINGS[@]})); then
  XCODEBUILD_ARGV+=("${XCODEBUILD_SETTINGS[@]}")
fi
if ((${#TEST_ARGS[@]})); then
  XCODEBUILD_ARGV+=("${TEST_ARGS[@]}")
fi

set +e
xcodebuild "${XCODEBUILD_ARGV[@]}"
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
  echo "xcodebuild test failed with status $STATUS"
  echo "Result bundle: $RESULT_BUNDLE"
  print_failure_summary
  exit "$STATUS"
fi

echo "All tests passed."
