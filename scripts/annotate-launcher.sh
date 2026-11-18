#!/bin/bash
# Runs the bundled universal binary; falls back to building from source.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname)" != "Darwin" ]]; then
  echo "screen-annotator only runs on macOS." >&2; exit 1
fi
BIN="$ROOT/bin/annotate"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/release/annotate"
  [[ -x "$BIN" ]] || (cd "$ROOT" && swift build -c release >&2)
fi
exec "$BIN" "$@"
