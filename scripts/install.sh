#!/bin/bash
# Build a release binary and install it to ~/.local/bin/annotate (no sudo).
set -euo pipefail
cd "$(dirname "$0")/.."
PREFIX="${PREFIX:-$HOME/.local}"
swift build -c release
mkdir -p "$PREFIX/bin"
# Stop a running overlay so the new binary takes over.
"$PREFIX/bin/annotate" quit >/dev/null 2>&1 || true
install -m 0755 .build/release/annotate "$PREFIX/bin/annotate"
echo "Installed $PREFIX/bin/annotate"
echo
echo "Try it now (1-minute interactive walkthrough):"
echo "  $PREFIX/bin/annotate tutorial"
echo
echo "Register with Claude Code:"
echo "  claude mcp add --scope user screen-annotator -- $PREFIX/bin/annotate mcp"
