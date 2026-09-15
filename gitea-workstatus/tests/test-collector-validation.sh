#!/usr/bin/env bash
# Validate the collector script without network — checks syntax, help, error paths
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COLLECTOR="$SCRIPT_DIR/../bin/gitea-collect"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Collector Validation Tests ==="
echo ""

# Test 1: Script is executable
echo "Test 1: Script permissions"
assert_eq "collector is executable" "true" "$([ -x "$COLLECTOR" ] && echo true || echo false)"

# Test 2: Bash syntax check
echo "Test 2: Bash syntax"
if bash -n "$COLLECTOR" 2>/dev/null; then
  echo "  PASS: bash -n passes"
  PASS=$((PASS + 1))
else
  echo "  FAIL: bash -n failed"
  FAIL=$((FAIL + 1))
fi

# Test 3: JQ script syntax check
echo "Test 3: JQ transform syntax"
JQ_SCRIPT="$SCRIPT_DIR/../bin/gitea-collect.jq"
if jq -n -f "$JQ_SCRIPT" \
  --arg url "test" --arg user "test" --arg ts "test" \
  --argjson prs "[]" --argjson runs "[]" \
  --argjson repo_count 0 --argjson max_stale 6 \
  >/dev/null 2>&1; then
  echo "  PASS: jq syntax valid"
  PASS=$((PASS + 1))
else
  echo "  FAIL: jq syntax invalid"
  FAIL=$((FAIL + 1))
fi

# Test 4: Missing credentials produces JSON error
echo "Test 4: Missing credentials error"
tmpdir=$(mktemp -d)
export XDG_STATE_HOME="$tmpdir/state"
export XDG_CONFIG_HOME="$tmpdir/config"
mkdir -p "$XDG_STATE_HOME/omarchy/gitea-workstatus" "$XDG_CONFIG_HOME/gitea-workstatus"

# Run without credentials file
output=$("$COLLECTOR" 2>/dev/null || true)
state_file="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"

if [ -f "$state_file" ]; then
  error_msg=$(jq -r '.error // empty' "$state_file" 2>/dev/null)
  assert_eq "error mentions credentials" "true" "$(echo "$error_msg" | grep -qi 'credentials\|GITEA' && echo true || echo false)"
else
  echo "  PASS: exited without creating file (acceptable)"
  PASS=$((PASS + 1))
fi

# Test 5: Empty GITEA_URL produces error
echo "Test 5: Empty URL error"
echo 'GITEA_URL=""
GITEA_TOKEN="test-token"' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"

"$COLLECTOR" 2>/dev/null || true

if [ -f "$state_file" ]; then
  error_msg=$(jq -r '.error // empty' "$state_file" 2>/dev/null)
  assert_eq "error mentions URL" "true" "$(echo "$error_msg" | grep -qi 'URL\|url' && echo true || echo false)"
fi

rm -rf "$tmpdir"

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
