#!/bin/bash
# Build a universal (Apple Silicon + Intel) release and stage distributables:
#   bin/annotate                      bundled binary for the Claude Code plugin
#   dist/annotate-<ver>-macos.tar.gz  standalone download
#   dist/mcpb/                        staged Claude Desktop extension (pack with `npx @anthropic-ai/mcpb pack dist/mcpb`)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(grep -m1 'let annotatorVersion' Sources/annotate/Daemon.swift | sed -E 's/.*"(.*)".*/\1/')"
swift build -c release --arch arm64 --arch x86_64
OUT=".build/out/Products/Release/annotate"
[[ -x "$OUT" ]] || OUT=".build/apple/Products/Release/annotate"
lipo -archs "$OUT"

install -m 0755 "$OUT" bin/annotate
rm -rf dist && mkdir -p dist/mcpb/server
tar -czf "dist/annotate-$VERSION-macos.tar.gz" -C bin annotate -C .. README.md
install -m 0755 "$OUT" dist/mcpb/server/annotate
sed "s/__VERSION__/$VERSION/" packaging/mcpb/manifest.json > dist/mcpb/manifest.json
cp README.md dist/mcpb/
( cd dist && shasum -a 256 *.tar.gz > SHA256SUMS )
echo "Built $VERSION:"; ls -la bin/annotate dist
