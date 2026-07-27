#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# generate_pigeon.sh — Regenerate the Pigeon platform-channel bindings.
#
# ALWAYS run this instead of `dart run pigeon` directly.
#
# Pigeon does not backtick-escape Kotlin hard keywords in the generated
# `package` declaration. This plugin's Android package is
# `in.sudhi.native_datastore`, and `in` is a reserved Kotlin keyword, so the
# raw generated file fails to compile with:
#
#   Messages.g.kt: Syntax error: Package name must be a '.'-separated identifier list.
#
# This wrapper regenerates the bindings and then rewrites the offending
# `package` line to the escaped form (`package `in`.sudhi.native_datastore`),
# matching the hand-written Kotlin sources.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/.."

KOTLIN_OUT="android/src/main/kotlin/in/sudhi/native_datastore/Messages.g.kt"

echo "Running pigeon..."
dart run pigeon --input pigeons/messages.dart

echo "Escaping reserved Kotlin keyword 'in' in generated package declaration..."
# Only the exact unescaped package line is rewritten; a no-op if already escaped.
sed -i '' 's|^package in\.sudhi\.native_datastore$|package `in`.sudhi.native_datastore|' "$KOTLIN_OUT"

# Verify the fix took (guards against pigeon changing the output path/format).
if grep -q '^package in\.sudhi\.native_datastore$' "$KOTLIN_OUT"; then
  echo "ERROR: failed to escape 'in' keyword in $KOTLIN_OUT" >&2
  exit 1
fi

echo "Done. Bindings regenerated and Kotlin package escaped."
