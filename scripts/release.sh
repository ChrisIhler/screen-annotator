#!/bin/bash
# Publish the version in Sources/annotate/Daemon.swift: build, test, tag, push, GitHub release.
# Usage: scripts/release.sh            (run from a clean, committed main branch)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(grep -m1 'let annotatorVersion' Sources/annotate/Daemon.swift | sed -E 's/.*"(.*)".*/\1/')"
grep -q "\"$VERSION\"" .claude-plugin/plugin.json || { echo "plugin.json version != $VERSION"; exit 1; }
grep -q "^## $VERSION" CHANGELOG.md || { echo "CHANGELOG has no $VERSION entry"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }
./scripts/build-release.sh
[[ -z "$(git status --porcelain)" ]] || { git add bin/annotate; git commit -m "Update bundled binary for $VERSION"; }
tests/run.sh "$PWD/bin/annotate"
git tag -a "v$VERSION" -m "v$VERSION"
git push origin main "v$VERSION"
NOTES=$(awk '/^## '"$VERSION"'/{f=1;next} /^## /{f=0} f' CHANGELOG.md)
gh release create "v$VERSION" "dist/annotate-$VERSION-macos.tar.gz" dist/SHA256SUMS \
  --title "Screen Annotator $VERSION" --notes "$NOTES

**Install:** Claude Code: \`/plugin install screen-annotator --marketplace ChrisIhler/screen-annotator\` · Any MCP client: download the tarball below and see the README."
echo "Released https://github.com/ChrisIhler/screen-annotator/releases/tag/v$VERSION"
