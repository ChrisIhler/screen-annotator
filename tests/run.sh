#!/bin/bash
# End-to-end tests: CLI, MCP protocol, daemon, shapes, clicks, errors.
# Usage: tests/run.sh [path/to/annotate]   (needs a Mac with a display; draws briefly)
set -uo pipefail
BIN="${1:-$(cd "$(dirname "$0")/.." && pwd)/.build/release/annotate}"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; echo "      $2"; }
check() { # name, command, expected substring
  local out; out="$(eval "$2" 2>&1)"
  if [[ "$out" == *"$3"* ]]; then ok "$1"; else bad "$1" "expected '$3' in: ${out:0:300}"; fi
}
mcp() { printf '%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' "$@" | "$BIN" mcp; }
call() { echo "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"; }

echo "Testing $BIN"
"$BIN" quit >/dev/null 2>&1; sleep 0.3

echo "CLI"
check "version"              "'$BIN' --version" "."
check "help"                 "'$BIN' help" "USAGE"
check "unknown command fails" "'$BIN' bogus; echo rc=\$?" "rc=2"
check "auto-starts daemon"   "'$BIN' displays" '"displays"'
check "ping"                 "'$BIN' ping" '"ok" : true'

echo "Shapes"
for s in "circle x=100 y=100 radius=40" "circle x=100 y=100 width=80 height=40" "rect x=10 y=10 width=50 height=50" \
         "highlight x=10 y=10 width=50 height=20" "arrow from_x=10 from_y=10 to_x=200 to_y=200" \
         "label x=20 y=20 text=hi" "marker x=50 y=50 number=3" "spotlight x=10 y=10 width=100 height=100"; do
  check "draw ${s%% *} (${s#* })" "'$BIN' $s id=t duration_seconds=5" '"drawn"'
done
check "fraction units"       "'$BIN' circle x=0.5 y=0.5 radius=0.1 units=fraction id=t" '"bounds"'
check "urgency prefixes label" "'$BIN' rect x=1 y=1 width=5 height=5 urgency=urgent label=Go id=t" '🔴 Go'
check "display by position"  "'$BIN' marker x=10 y=10 number=1 display=left id=t" '"drawn"'
check "display=all"          "'$BIN' json '{\"cmd\":\"draw\",\"display\":\"all\",\"shape\":{\"type\":\"marker\",\"x\":20,\"y\":20,\"number\":1,\"id\":\"t\"}}'" '"drawn"'
check "list shows marks"     "'$BIN' list" '"id" : "t"'
check "clear by id"          "'$BIN' clear id=t" '"remaining" : 0'

echo "Errors"
check "missing field"        "'$BIN' rect x=1 y=1" 'missing required number'
check "bad display"          "'$BIN' circle x=1 y=1 radius=2 display=nope" 'No display matches'
check "bad type"             "'$BIN' json '{\"cmd\":\"draw\",\"shape\":{\"type\":\"blob\"}}'" 'Unknown shape type'
check "bad json"             "'$BIN' json '{nope'" 'expects one JSON object'
"$BIN" json '{"cmd":"draw","shapes":[{"type":"marker","x":1,"y":1,"number":1,"id":"atomic"},{"type":"rect"}]}' >/dev/null
check "atomic batch (bad shape draws nothing)" "'$BIN' list | grep -q atomic && echo partial || echo none" 'none'

echo "Clicks"
"$BIN" json '{"cmd":"events"}' >/dev/null; "$BIN" json '{"cmd":"events"}' >/dev/null
check "task mark"            "'$BIN' marker x=40 y=40 number=1 id=step done_text=Finish" '"task" : true'
check "simulated done click" "'$BIN' json '{\"cmd\":\"_simulate_click\",\"id\":\"step\"}'" '"ok" : true'
check "wait returns done"    "'$BIN' wait id=step timeout=2" '"action" : "done"'
check "click consumed once"  "'$BIN' wait id=step timeout=0; echo rc=\$?" 'rc=1'
"$BIN" marker x=40 y=40 number=2 id=gone >/dev/null
"$BIN" json '{"cmd":"_simulate_click","id":"gone","action":"dismissed"}' >/dev/null
check "dismiss removes mark" "'$BIN' wait id=gone timeout=2 && '$BIN' list" '"annotations" : ['

echo "Guided mode"
"$BIN" json '{"cmd":"events"}' >/dev/null
check "guide starts"         "'$BIN' guide '{\"id\":\"g\",\"steps\":[{\"title\":\"One\",\"shapes\":[{\"type\":\"marker\",\"x\":50,\"y\":50,\"number\":1}]},{\"type\":\"rect\",\"x\":10,\"y\":10,\"width\":40,\"height\":40,\"label\":\"Two\"}]}'" '"steps" : 2'
check "step 1 shown"         "'$BIN' list" 'Step 1\/2: One'
check "step has Next button" "'$BIN' list" '"task" : true'
"$BIN" json '{"cmd":"_simulate_click","id":"g.1"}' >/dev/null; sleep 1
check "advances to step 2"   "'$BIN' list" 'Step 2\/2: Two'
"$BIN" json '{"cmd":"_simulate_click","id":"g.2"}' >/dev/null; sleep 1.2
check "guide completes"      "'$BIN' wait id=g timeout=2" '"action" : "completed"'
"$BIN" guide '[{"type":"marker","x":5,"y":5,"number":1},{"type":"marker","x":5,"y":5,"number":2}]' id=c >/dev/null
"$BIN" json '{"cmd":"_simulate_click","id":"c.1","action":"dismissed"}' >/dev/null
check "✕ cancels guide"      "'$BIN' wait id=c timeout=2" '"action" : "cancelled"'
check "bad step rejected"    "'$BIN' guide '[{\"type\":\"rect\"}]'" 'missing required number'

echo "Windows"
check "list_windows"         "'$BIN' windows" '"windows"'
check "unknown window"       "'$BIN' rect window=NoSuchAppXYZ x=1 y=1 width=5 height=5" 'No visible window matches'
HELPER="$(cd "$(dirname "$0")/.." && pwd)/.build/moving-window"
if [[ ! -x "$HELPER" ]]; then swiftc -O "$(dirname "$0")/MovingWindow.swift" -o "$HELPER" 2>/dev/null; fi
if [[ -x "$HELPER" ]]; then
  "$HELPER" & sleep 1
  check "anchor to window"   "'$BIN' rect window=moving-window x=10 y=10 width=100 height=50 id=w" '"window" : "moving-window"'
  B1=$("$BIN" list | grep -A1 '"bounds"' | tail -1 | tr -dc '0-9')
  sleep 2
  B2=$("$BIN" list | grep -A1 '"bounds"' | tail -1 | tr -dc '0-9')
  check "mark follows window" "echo \$((B2 - B1))" '200'
  sleep 2.5
  check "hidden when window gone" "'$BIN' list" '"window_visible" : false'
  wait; "$BIN" clear >/dev/null
else
  echo "  - skipped window-follow test (no swiftc)"
fi

echo "MCP"
check "initialize"           "mcp" '"serverInfo"'
check "tools/list"           "mcp '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}'" 'wait_for_click'
check "guide tool listed"    "mcp '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}'" '"name":"guide"'
check "tool call draws"      "mcp '$(call draw_arrow '{"from_x":1,"from_y":1,"to_x":50,"to_y":50,"id":"m"}')'" '"isError":false'
check "tool error flagged"   "mcp '$(call draw_rect '{"x":1}')'" '"isError":true'
check "unknown tool"         "mcp '$(call nope '{}')'" 'Unknown tool'
check "unknown method"       "mcp '{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"nope\"}'" '-32601'
check "wait_for_click poll"  "mcp '$(call wait_for_click '{"timeout_seconds":0}')'" 'clicked'
check "clear via MCP"        "mcp '$(call clear '{}')'" 'cleared'

"$BIN" clear >/dev/null
echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
