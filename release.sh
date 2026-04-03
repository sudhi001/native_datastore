#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------
# release.sh — Create a release commit for native_datastore
#
# Usage:
#   ./release.sh 1.0.0
#   ./release.sh 1.2.3
#
# What it does:
#   1. Validates the version format (x.y.z)
#   2. Updates pubspec.yaml with the new version
#   3. Updates CHANGELOG.md with a new entry
#   4. Runs flutter analyze and flutter test
#   5. Creates a commit: "RELEASE 1.0.0"
#   6. Creates a git tag: v1.0.0
#
# Push to trigger the publish workflow:
#   git push && git push --tags
# -----------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
info()  { echo -e "${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }

# ---- Validate input ----
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  error "Usage: ./release.sh <version>  (e.g. ./release.sh 1.0.0)"
fi

if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  error "Invalid version format '$VERSION'. Expected x.y.z (e.g. 1.0.0)"
fi

# ---- Ensure clean working tree ----
if [ -n "$(git status --porcelain)" ]; then
  error "Working tree is not clean. Commit or stash your changes first."
fi

# ---- Ensure we're on main ----
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
  warn "Warning: You are on branch '$BRANCH', not 'main'."
  read -rp "Continue anyway? [y/N] " CONFIRM
  if [[ "$CONFIRM" != [yY] ]]; then
    exit 1
  fi
fi

# ---- Check current version ----
CURRENT_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
info "Current version: $CURRENT_VERSION"
info "New version:     $VERSION"

if [ "$CURRENT_VERSION" = "$VERSION" ]; then
  error "pubspec.yaml is already at version $VERSION"
fi

# ---- Check tag doesn't already exist ----
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
  error "Tag v$VERSION already exists"
fi

# ---- Update pubspec.yaml ----
info "Updating pubspec.yaml..."
sed -i.bak "s/^version: .*/version: $VERSION/" pubspec.yaml
rm -f pubspec.yaml.bak

# ---- Update CHANGELOG.md ----
info "Updating CHANGELOG.md..."
DATE=$(date +%Y-%m-%d)
CHANGELOG_ENTRY="## $VERSION\n\n* Released on $DATE.\n"

if [ -f CHANGELOG.md ]; then
  # Insert new entry at the top of the file
  {
    echo -e "$CHANGELOG_ENTRY"
    cat CHANGELOG.md
  } > CHANGELOG.md.tmp
  mv CHANGELOG.md.tmp CHANGELOG.md
else
  echo -e "$CHANGELOG_ENTRY" > CHANGELOG.md
fi

# ---- Run checks ----
info "Running flutter pub get..."
flutter pub get

info "Running flutter analyze..."
flutter analyze

info "Running flutter test..."
flutter test

# ---- Dry run publish ----
info "Running publish dry run..."
flutter pub publish --dry-run

# ---- Commit & tag ----
info "Creating release commit..."
git add pubspec.yaml CHANGELOG.md pubspec.lock
git commit -m "RELEASE $VERSION"
git tag "v$VERSION"

info ""
info "Release $VERSION is ready!"
info ""
info "To publish, run:"
info "  git push && git push --tags"
