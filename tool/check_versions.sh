#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# check_versions.sh — Fail if the native manifests disagree with pubspec.yaml.
#
# pubspec.yaml, android/build.gradle.kts and ios/native_datastore.podspec each
# carry a version string, and nothing at build time reads the latter two — so
# they quietly drifted to 1.7.1, 1.6.2 and 1.5.3 respectively. release.sh now
# rewrites them; this is the gate that proves it happened.
#
# Usage: ./tool/check_versions.sh
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/.."

VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr -d '[:space:]')
[ -n "$VERSION" ] || { echo "ERROR: no 'version:' in pubspec.yaml" >&2; exit 1; }

GRADLE_VERSION=$(grep -E '^version = ' android/build.gradle.kts | sed -E 's/.*"(.*)".*/\1/')
POD_VERSION=$(grep -E "^\s*s\.version" ios/native_datastore.podspec | sed -E "s/.*'(.*)'.*/\1/")

status=0
printf '  %-34s %s\n' "pubspec.yaml" "$VERSION"
for pair in "android/build.gradle.kts:$GRADLE_VERSION" "ios/native_datastore.podspec:$POD_VERSION"; do
  file="${pair%:*}"
  found="${pair##*:}"
  if [ "$found" = "$VERSION" ]; then
    printf '  %-34s %s\n' "$file" "$found"
  else
    printf '  %-34s %s  <-- expected %s\n' "$file" "${found:-<none>}" "$VERSION"
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "" >&2
  echo "ERROR: native version strings do not match pubspec.yaml ($VERSION)." >&2
  echo "       ./release.sh rewrites them; run it, or fix them by hand." >&2
  exit 1
fi

echo ""
echo "OK: all version strings agree on $VERSION."
