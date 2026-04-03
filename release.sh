#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------
# release.sh — Release and publish native_datastore to pub.dev
#
# Usage:
#   ./release.sh 1.0.0
#
# What it does:
#   1. Validates the version format (x.y.z)
#   2. Updates pubspec.yaml and CHANGELOG.md
#   3. Runs flutter analyze and flutter test
#   4. Creates a commit: "RELEASE x.y.z" and tag: vx.y.z
#   5. Publishes to pub.dev
#   6. Pushes commit and tag to origin
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

# ---- Commit (so dry-run sees a clean tree) ----
info "Creating release commit..."
git add pubspec.yaml CHANGELOG.md
git commit -m "RELEASE $VERSION"

# ---- Dry run publish ----
info "Running publish dry run..."
if ! flutter pub publish --dry-run; then
  warn "Dry run failed. Rolling back release commit..."
  git reset --soft HEAD~1
  git restore --staged pubspec.yaml CHANGELOG.md
  git checkout -- pubspec.yaml CHANGELOG.md
  error "Publish dry run failed. Commit has been rolled back."
fi

# ---- Publish to pub.dev ----
info "Publishing to pub.dev..."
if ! flutter pub publish --force; then
  warn "Publish failed. Rolling back release commit..."
  git reset --soft HEAD~1
  git restore --staged pubspec.yaml CHANGELOG.md
  git checkout -- pubspec.yaml CHANGELOG.md
  error "Publish to pub.dev failed. Commit has been rolled back."
fi

# ---- Tag and push ----
git tag "v$VERSION"

info "Pushing to origin..."
git push
git push --tags

info ""
info "Released $VERSION to pub.dev!"
info "  https://pub.dev/packages/native_datastore"
