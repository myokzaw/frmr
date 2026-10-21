#!/bin/bash
# Usage: qa/test-consolidation/list-tests.sh <target: frmrTests|frmrUITests> <out.txt> [simulator-id]
# Lists every test (suite/name) via xcodebuild -enumerate-tests. Needs a prior build-for-testing.
set -euo pipefail
cd "$(dirname "$0")/../.."
TARGET="${1:-frmrTests}"; OUT="${2:-/dev/stdout}"; SIM="${3:-37A97720-A320-4FAA-AD16-4CEBE632C793}"
TMP="qa/DerivedData/enum-$$.json"
xcodebuild -project frmr.xcodeproj -scheme frmr -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath qa/DerivedData -only-testing:"$TARGET" test-without-building \
  -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
  -test-enumeration-output-path "$TMP" >/dev/null 2>&1
python3 -I - "$TMP" > "$OUT" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
ids=sorted(t['identifier'] for v in d['values'] for t in v['enabledTests'])
suites={i.split('/')[1] for i in ids}
print(f"# {len(ids)} tests in {len(suites)} suites (parameterised tests count once)")
for i in ids: print(i)
PY
rm -f "$TMP"
