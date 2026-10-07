#!/usr/bin/env bash
# Constraint guard for frmr production Swift (CLAUDE.md hard constraints).
#   --all   scan frmr/ ; exit 1 on violations
#   --hook  read PostToolUse JSON on stdin ; scan that one file ; exit 2 on violations
# Force-unwrap detection is deliberately absent: regex is too noisy, QA reviews it.

set -u

ROOT="${FRMR_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Each entry is an ERE matched against code with comments stripped.
BANNED=(
  'URLSession'
  'URLRequest'
  'import[[:space:]]+Network'
  'import[[:space:]]+Combine'
  'ObservableObject'
  '@Published'
  'UIImagePickerController'
  'PHPickerViewController'
  '\.videoOrientation'
  'Timer\.scheduledTimer'
)

# Apple SDK modules frmr may import. Anything else counts as third-party.
APPLE_IMPORTS='^(Foundation|SwiftUI|SwiftData|Observation|UIKit|AVFoundation|CoreImage|CoreGraphics|CoreMedia|CoreVideo|CoreMotion|CoreHaptics|CoreText|CoreLocation|ImageIO|Photos|PhotosUI|QuartzCore|Accelerate|Vision|UniformTypeIdentifiers|OSLog|os|Metal|MetalKit|Darwin|Dispatch|Swift|Testing|XCTest)$'

VIOLATIONS=()
WARNINGS=()

scan_file() {
  local file="$1" rel="${1#"$ROOT"/}"
  local n=0 line code mod

  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    code="${line%%//*}"
    [ -z "${code//[[:space:]]/}" ] && continue

    for pat in "${BANNED[@]}"; do
      if printf '%s' "$code" | grep -Eq -- "$pat"; then
        VIOLATIONS+=("$rel:$n: forbidden '$pat' — $(printf '%s' "$line" | sed 's/^[[:space:]]*//')")
      fi
    done

    if [[ "$code" =~ ^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*(public[[:space:]]+|internal[[:space:]]+)?import[[:space:]]+([A-Za-z0-9_]+) ]]; then
      mod="${BASH_REMATCH[3]}"
      if ! printf '%s' "$mod" | grep -Eq "$APPLE_IMPORTS"; then
        VIOLATIONS+=("$rel:$n: third-party import '$mod' (flag it and wait for approval)")
      fi
    fi
  done < "$file"

  # warn only: an OPEN placeholder should have its value in Constants nearby
  local open_line lo hi
  while IFS=: read -r open_line _; do
    [ -z "$open_line" ] && continue
    lo=$((open_line - 5)); [ "$lo" -lt 1 ] && lo=1
    hi=$((open_line + 5))
    if ! sed -n "${lo},${hi}p" "$file" | grep -q 'Constants\.'; then
      WARNINGS+=("$rel:$open_line: // OPEN: with no Constants. value within 5 lines")
    fi
  done < <(grep -n '// OPEN:' "$file")
}

report() {
  local w
  for w in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do echo "warn: $w" >&2; done
  if [ "${#VIOLATIONS[@]}" -gt 0 ]; then
    echo "frmr-guard: ${#VIOLATIONS[@]} violation(s):" >&2
    local v
    for v in "${VIOLATIONS[@]}"; do echo "  - $v" >&2; done
    return 1
  fi
  return 0
}

case "${1:-}" in
  --all)
    while IFS= read -r f; do scan_file "$f"; done < <(find "$ROOT/frmr" -name '*.swift' -not -path '*/frmrTests/*' | sort)
    if report; then echo "frmr-guard: clean (${#WARNINGS[@]} OPEN warning(s))"; exit 0; fi
    exit 1
    ;;
  --hook)
    command -v jq >/dev/null 2>&1 || { echo "frmr-guard: jq not found" >&2; exit 0; }
    path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    case "$path" in
      "$ROOT"/frmr/*.swift) ;;
      frmr/*.swift) path="$ROOT/$path" ;;
      *) exit 0 ;;
    esac
    [ -f "$path" ] || exit 0
    scan_file "$path"
    if report; then exit 0; fi
    exit 2
    ;;
  *)
    echo "usage: $0 --all | --hook" >&2
    exit 64
    ;;
esac
