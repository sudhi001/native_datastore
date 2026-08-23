#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# check_coverage.sh — Fail if unit-test line coverage drops below a threshold.
#
# The package sits at 100% line coverage. Without a gate that erodes silently,
# exactly like the formatter drift that quietly cost 10 pub.dev points.
#
# Usage:
#   ./tool/check_coverage.sh          # require 100%
#   ./tool/check_coverage.sh 95       # require 95%
#
# Expects coverage/lcov.info to exist (run `flutter test --coverage` first).
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/.."

THRESHOLD="${1:-100}"
LCOV="coverage/lcov.info"

if [[ ! -f "$LCOV" ]]; then
  echo "ERROR: $LCOV not found — run 'flutter test --coverage' first." >&2
  exit 1
fi

status=0
awk -F: -v threshold="$THRESHOLD" '
  /^SF:/        { file = $2; total = 0; hit = 0 }
  /^DA:/        { split($2, a, ","); total++; if (a[2] > 0) hit++ }
  /^end_of_record/ {
    printf "  %-42s %4d/%4d  %6.2f%%\n", file, hit, total, (total ? hit * 100 / total : 100)
    grandTotal += total
    grandHit   += hit
  }
  END {
    if (grandTotal == 0) {
      print "ERROR: no DA records in lcov.info — nothing was measured." > "/dev/stderr"
      exit 1
    }
    pct = grandHit * 100 / grandTotal
    printf "  %-42s %4d/%4d  %6.2f%%\n", "TOTAL", grandHit, grandTotal, pct
    if (pct + 0.0000001 < threshold) {
      printf "\nERROR: line coverage %.2f%% is below the required %s%%.\n", pct, threshold > "/dev/stderr"
      exit 1
    }
    printf "\nOK: line coverage %.2f%% meets the required %s%%.\n", pct, threshold
  }
' "$LCOV" || status=$?

# Name the uncovered lines so a failure is actionable.
UNCOVERED=$(awk -F: '/^SF:/ { f = $2 } /^DA:/ { split($2, a, ","); if (a[2] == 0) print "  " f ":" a[1] }' "$LCOV")
if [[ -n "$UNCOVERED" ]]; then
  echo ""
  echo "Uncovered lines:"
  echo "$UNCOVERED"
fi

exit "$status"
