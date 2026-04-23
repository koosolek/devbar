#!/usr/bin/env bash
# Cut a new DevBar release.
#
# Usage:
#   scripts/cut-release.sh               → bump the patch (0.1.0 → 0.1.1)
#   scripts/cut-release.sh minor         → bump the minor (0.1.3 → 0.2.0)
#   scripts/cut-release.sh major         → bump the major (0.9.4 → 1.0.0)
#   scripts/cut-release.sh 1.2.3         → explicit version
#
# What it does:
#   1. Bumps MARKETING_VERSION across the xcodeproj.
#   2. Commits the change as "Release vX.Y.Z".
#   3. Tags the commit as vX.Y.Z.
#   4. Pushes the commit and the tag to origin.
#
# The tag push triggers .github/workflows/release.yml, which builds
# DevBar.app, zips it, and publishes a GitHub Release with the binary
# attached. That's the artifact non-devs download.

set -euo pipefail

PROJECT_FILE="DevBar.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "error: must be run from the repo root" >&2
    exit 1
fi

# Require a clean tree so we don't bundle unrelated changes into the
# "Release vX.Y.Z" commit.
if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree not clean — commit or stash first" >&2
    git status --short
    exit 1
fi

# Make sure we're on main so tags land on the shipping branch.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "error: cut from main, currently on '$CURRENT_BRANCH'" >&2
    exit 1
fi

CURRENT=$(grep -m1 'MARKETING_VERSION = ' "$PROJECT_FILE" | sed -E 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/')

if [ -z "${CURRENT}" ]; then
    echo "error: could not read MARKETING_VERSION from $PROJECT_FILE" >&2
    exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "${1:-patch}" in
    patch)
        NEXT="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    minor)
        NEXT="$MAJOR.$((MINOR + 1)).0"
        ;;
    major)
        NEXT="$((MAJOR + 1)).0.0"
        ;;
    [0-9]*.[0-9]*.[0-9]*)
        NEXT="$1"
        ;;
    *)
        echo "error: unrecognised argument '$1' — use patch|minor|major|X.Y.Z" >&2
        exit 1
        ;;
esac

TAG="v$NEXT"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists" >&2
    exit 1
fi

echo "Cutting release: $CURRENT → $NEXT"
echo

# sed -i behaves differently on macOS vs GNU, so use the macOS form with
# an empty backup suffix.
sed -i '' -E "s/MARKETING_VERSION = $CURRENT;/MARKETING_VERSION = $NEXT;/g" "$PROJECT_FILE"

# Sanity check: every occurrence got bumped (app + tests targets).
REMAINING=$(grep -c "MARKETING_VERSION = $CURRENT;" "$PROJECT_FILE" || true)
if [ "$REMAINING" -ne 0 ]; then
    echo "error: $REMAINING entries still at $CURRENT after sed" >&2
    exit 1
fi

git add "$PROJECT_FILE"
git commit -m "Release $TAG"
git tag -a "$TAG" -m "Release $TAG"

echo
echo "Commit + tag created. Pushing to origin..."
git push origin main
git push origin "$TAG"

echo
echo "Done. The release workflow is now building the zip and drafting"
echo "the GitHub Release — watch it at:"
echo "  https://github.com/koosolek/devbar/actions"
