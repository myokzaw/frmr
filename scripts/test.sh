#!/usr/bin/env bash
# frmr test runner — one entry point so parallel agents never fight over a
# simulator or a build folder, and only pay for what they need.
#
# Each role gets its own simulator and DerivedData folder:
#   lead     → frmr-lead      build/lead
#   backend  → frmr-backend   build/backend
#   frontend → frmr-frontend  build/frontend
#   qa       → frmr-qa        qa/DerivedData
#   restyle  → frmr-restyle   build/restyle (second frontend agent; UI shards frmr-ui-4…6)
# UI tests are sharded across frmr-ui-1…3 and run concurrently.
#
# Usage (from the frmr/ folder, the one with frmr.xcodeproj):
#   scripts/test.sh fast  <role>            unit tests minus the slow matrix/timing suites
#   scripts/test.sh suite <role> Suite...   only the named suites (e.g. FilmModelTests)
#   scripts/test.sh unit  <role>            every unit test
#   scripts/test.sh ui    <role> [Class...] UI tests, sharded over 3 simulators
#   scripts/test.sh all   <role>            unit + UI (end of a round)
# Add --no-build after the role to reuse the last build (re-runs only).
#
# Exit code is non-zero if the build or any test fails, or if Swift warnings
# appear. Full logs go to build/test-logs/.

set -uo pipefail

PROJECT="frmr.xcodeproj"
SCHEME="frmr"
# Suites excluded from the fast tier: exhaustive matrices and timing. They
# still run in `unit` and `all` (QA and the lead run those at round end).
SLOW_SUITES=(
  "frmrTests/StripLookRegressionTests"
  "frmrTests/FilmAtCaptureRegressionTests"
  "frmrTests/StripRenderTimingTests"
)
UI_SHARDS=(frmr-ui-1 frmr-ui-2 frmr-ui-3)   # the restyle role uses frmr-ui-4…6 (set below)

die() { echo "test.sh: $*" >&2; exit 2; }

[ -d "$PROJECT" ] || die "run from the folder containing $PROJECT"
MODE="${1:-}"; ROLE="${2:-}"
[ -n "$MODE" ] && [ -n "$ROLE" ] || die "usage: scripts/test.sh <fast|suite|unit|ui|all> <lead|backend|frontend|restyle|qa> [--no-build] [names...]"
shift 2
BUILD=1
if [ "${1:-}" = "--no-build" ]; then BUILD=0; shift; fi

case "$ROLE" in
  lead) SIM="frmr-lead"; DD="build/lead" ;;
  backend) SIM="frmr-backend"; DD="build/backend" ;;
  frontend) SIM="frmr-frontend"; DD="build/frontend" ;;
  qa) SIM="frmr-qa"; DD="qa/DerivedData" ;;
  restyle) SIM="frmr-restyle"; DD="build/restyle"; UI_SHARDS=(frmr-ui-4 frmr-ui-5 frmr-ui-6) ;;
  *) die "unknown role '$ROLE'" ;;
esac

udid_for() {
  xcrun simctl list devices | grep " $1 (" | grep -oE "[0-9A-F]{8}-[0-9A-F-]{27}" | head -1
}
SIM_ID="$(udid_for "$SIM")"
[ -n "$SIM_ID" ] || die "simulator '$SIM' not found — see docs/testing.md (Workflow) to create it"

LOGS="build/test-logs"; mkdir -p "$LOGS"

# A cold simulator makes the first test launch fail with "Busy"; boot it
# and wait until it is ready before anything runs on it.
ensure_booted() {
  xcrun simctl boot "$1" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$1" -b >/dev/null 2>&1 || true
}
ensure_booted "$SIM_ID"
STAMP="$(date +%H%M%S)"

check_log() {
  # Swift Testing prints its own summary; XCTest (UI) prints "Executed".
  local log="$1" label="$2" ok=0
  # Only real failures count: compiler/linker errors, xcodebuild's own
  # failure banner, and failing tests. Simulator log noise such as CoreData
  # "error:" lines from the app host is ignored.
  if grep -qE "\.swift:[0-9]+:[0-9]+: error:|^ld: |error: (linker|cannot|no such|unable)|\*\* (TEST|BUILD) FAILED|Test run with .* failed|' failed \(|Testing failed:" "$log"; then ok=1; fi
  if grep -qE "\.swift:[0-9]+:[0-9]+: warning" "$log"; then
    echo "  ✗ $label: Swift warnings (treated as failures)"; grep -E "\.swift:[0-9]+:[0-9]+: warning" "$log" | sort -u | head -5
    ok=1
  fi
  grep -E "Test run with|Executed [0-9]+ tests?, with|\*\* (TEST|BUILD) (SUCCEEDED|FAILED)" "$log" | tail -2 | sed "s/^/  $label: /"
  [ $ok -eq 0 ] || grep -E "\.swift:[0-9]+:[0-9]+: error:|' failed|✘|Testing failed:" "$log" | head -8 | sed "s/^/    /"
  return $ok
}

build_for_testing() {
  [ $BUILD -eq 1 ] || return 0
  local log="$LOGS/$ROLE-build-$STAMP.log"
  echo "→ build-for-testing ($ROLE, $DD)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath "$DD" \
    build-for-testing >"$log" 2>&1
  check_log "$log" "build" || { echo "  log: $log"; exit 1; }
}

run_unit() {
  # $@ = extra -only-testing / -skip-testing flags
  local log="$LOGS/$ROLE-unit-$STAMP.log"
  echo "→ unit tests on $SIM"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath "$DD" \
    -parallel-testing-enabled NO "$@" test-without-building >"$log" 2>&1
  check_log "$log" "unit"; local rc=$?
  echo "  log: $log"; return $rc
}

run_ui() {
  # $@ = optional UI test class names; default = every XCTestCase in frmrUITests
  local classes=("$@")
  if [ ${#classes[@]} -eq 0 ]; then
    while IFS= read -r c; do classes+=("$c"); done < <(
      grep -hoE "class [A-Za-z0-9_]+ *: *XCTestCase" frmrUITests/*.swift | awk '{print $2}' | tr -d ':' | sort -u)
  fi
  [ ${#classes[@]} -gt 0 ] || die "no UI test classes found"
  local n=${#UI_SHARDS[@]} pids=() logs=() i=0 rc=0
  for shard in "${UI_SHARDS[@]}"; do
    local id; id="$(udid_for "$shard")"; [ -n "$id" ] || die "simulator '$shard' not found"
    ensure_booted "$id"
    xcrun simctl addmedia "$id" qa/fixtures/strip-fixture-*.png >/dev/null 2>&1 || true
  done
  for shard in "${UI_SHARDS[@]}"; do
    local id flags=() j
    id="$(udid_for "$shard")"
    for ((j = i; j < ${#classes[@]}; j += n)); do flags+=("-only-testing:frmrUITests/${classes[$j]}"); done
    i=$((i + 1))
    [ ${#flags[@]} -gt 0 ] || continue
    local log="$LOGS/$ROLE-ui-$shard-$STAMP.log"; logs+=("$log")
    echo "→ UI shard $shard: ${flags[*]//-only-testing:frmrUITests\//}"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$DD" \
      -resultBundlePath "$LOGS/$ROLE-ui-$shard-$STAMP.xcresult" \
      -parallel-testing-enabled NO "${flags[@]}" test-without-building >"$log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  for log in "${logs[@]}"; do check_log "$log" "$(basename "$log" .log)" || rc=1; done
  return $rc
}

start=$(date +%s)
case "$MODE" in
  fast)
    build_for_testing
    skip=(); for s in "${SLOW_SUITES[@]}"; do skip+=("-skip-testing:$s"); done
    run_unit -only-testing:frmrTests "${skip[@]}"; rc=$? ;;
  suite)
    [ $# -gt 0 ] || die "suite mode needs at least one suite name"
    build_for_testing
    only=(); for s in "$@"; do only+=("-only-testing:frmrTests/$s"); done
    run_unit "${only[@]}"; rc=$? ;;
  unit)
    build_for_testing
    run_unit -only-testing:frmrTests; rc=$? ;;
  ui)
    build_for_testing
    run_ui "$@"; rc=$? ;;
  all)
    build_for_testing
    run_unit -only-testing:frmrTests; rc=$?
    BUILD=0; run_ui || rc=1 ;;
  *) die "unknown mode '$MODE'" ;;
esac
echo "done in $(( $(date +%s) - start ))s — $([ $rc -eq 0 ] && echo PASS || echo FAIL)"
exit $rc
