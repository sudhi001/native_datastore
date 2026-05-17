#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# release.sh — Trigger a release.
#
# Assumes you've already bumped `version:` in pubspec.yaml and written a
# CHANGELOG entry. This script:
#
#   1. Reads the version from pubspec.yaml and derives tag v{version}.
#   2. Confirms the tag does not yet exist locally or on origin.
#   3. Stages any working-tree changes and commits them (skipped if none).
#   4. Creates annotated tag v{version}.
#   5. Pushes the commit and the tag — which triggers
#      .github/workflows/release.yml, where tests run and (on pass) the
#      package is published to pub.dev via OIDC.
#
# Usage:
#   ./release.sh                       # commit message: "Release vX.Y.Z"
#   ./release.sh "fix typo in README"  # custom commit message
# -----------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
info()  { echo -e "${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }

# ---- Read version from pubspec.yaml ----
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr -d '[:space:]')
[ -z "$VERSION" ] && error "Could not read 'version:' from pubspec.yaml"
TAG="v$VERSION"
COMMIT_MSG="${1:-Release $TAG}"

info "Version: $VERSION"
info "Tag:     $TAG"
info "Commit:  $COMMIT_MSG"
echo

# ---- Branch sanity ----
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  warn "You are on branch '$BRANCH', not 'main'."
  read -rp "Continue anyway? [y/N] " CONFIRM
  [[ "$CONFIRM" != [yY] ]] && exit 1
fi

# ---- Tag doesn't already exist (local) ----
if git rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
  error "Tag $TAG already exists locally. Bump pubspec.yaml or delete the tag:
    git tag -d $TAG"
fi

# ---- Tag doesn't already exist (remote) ----
git fetch --tags --quiet origin 2>/dev/null || true
if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
  error "Tag $TAG already exists on origin. Bump pubspec.yaml or delete the remote tag:
    git push --delete origin $TAG"
fi

# ---- Show working tree state ----
if [ -n "$(git status --porcelain)" ]; then
  info "Pending changes (will be staged via 'git add -A'):"
  git status --short
else
  info "Working tree is clean — will tag current HEAD only."
fi
echo

read -rp "Proceed with commit, tag, and push? [y/N] " CONFIRM
[[ "$CONFIRM" != [yY] ]] && { info "Aborted."; exit 1; }

# ---- Stage & commit (skipped if nothing changed) ----
if [ -n "$(git status --porcelain)" ]; then
  info "Committing..."
  git add -A
  git commit -m "$COMMIT_MSG"
fi

# ---- Tag ----
info "Tagging $TAG..."
git tag -a "$TAG" -m "Release $TAG"

# ---- Push commit then tag ----
info "Pushing branch '$BRANCH'..."
git push origin "$BRANCH"

info "Pushing tag $TAG..."
git push origin "$TAG"

echo
info "Done. GitHub Actions is now running tests and publishing."
info "  https://github.com/sudhi001/native_datastore/actions"
