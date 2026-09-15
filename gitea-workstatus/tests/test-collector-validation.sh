#!/usr/bin/env bash
# Validate the collector script — syntax, error paths, and mocked execution.
# No real network or Gitea credentials needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COLLECTOR="$SCRIPT_DIR/../bin/gitea-collect"
MOCK_DIR="$SCRIPT_DIR/mock-responses"
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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qi "$needle"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Collector Validation Tests ==="
echo ""

# Test 1: Script can be invoked via bash
echo "Test 1: Script can be invoked via bash"
if bash -n "$COLLECTOR" 2>/dev/null; then
  echo "  PASS: bash -n passes"
  PASS=$((PASS + 1))
else
  echo "  FAIL: bash -n failed"
  FAIL=$((FAIL + 1))
fi

# Test 2: JQ script syntax check
echo "Test 2: JQ transform syntax"
JQ_SCRIPT="$SCRIPT_DIR/../bin/gitea-collect.jq"
if jq -n -f "$JQ_SCRIPT" \
  --arg url "test" --arg user "test" --arg ts "test" \
  --argjson prs "[]" --argjson runs "[]" \
  --argjson repo_count 0 --argjson max_stale 6 \
  --argjson repo_failed 0 --argjson repo_attempted 0 \
  >/dev/null 2>&1; then
  echo "  PASS: jq syntax valid"
  PASS=$((PASS + 1))
else
  echo "  FAIL: jq syntax invalid"
  FAIL=$((FAIL + 1))
fi

# Test 3: Missing credentials produces atomic JSON error
echo "Test 3: Missing credentials error"
tmpdir=$(mktemp -d)
export XDG_STATE_HOME="$tmpdir/state"
export XDG_CONFIG_HOME="$tmpdir/config"
mkdir -p "$XDG_STATE_HOME/omarchy/gitea-workstatus" "$XDG_CONFIG_HOME/gitea-workstatus"
state_file="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"

bash "$COLLECTOR" 2>/dev/null || true

if [ -f "$state_file" ]; then
  error_msg=$(jq -r '.error // empty' "$state_file" 2>/dev/null)
  assert_contains "error mentions credentials" "credentials" "$error_msg"
  if jq empty "$state_file" 2>/dev/null; then
    echo "  PASS: error output is valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: error output is not valid JSON"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: collector should write error JSON to state file"
  FAIL=$((FAIL + 1))
fi

# Test 4: Empty GITEA_URL produces error
echo "Test 4: Empty URL error"
printf 'GITEA_URL=""\nGITEA_TOKEN="test-token"\n' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"

rm -f "$state_file"
bash "$COLLECTOR" 2>/dev/null || true

if [ -f "$state_file" ]; then
  error_msg=$(jq -r '.error // empty' "$state_file" 2>/dev/null)
  assert_contains "error mentions URL" "URL" "$error_msg"
fi

# Test 5: Lock file is ownership-safe
echo "Test 5: Lock file ownership"
rm -f "$XDG_STATE_HOME/omarchy/gitea-workstatus/.collect.lock"
printf 'GITEA_URL="https://unreachable.test"\nGITEA_TOKEN="fake-token"\n' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"

echo "999999" > "$XDG_STATE_HOME/omarchy/gitea-workstatus/.collect.lock"
bash "$COLLECTOR" 2>/dev/null || true
if [ -f "$XDG_STATE_HOME/omarchy/gitea-workstatus/.collect.lock" ]; then
  lock_content=$(cat "$XDG_STATE_HOME/omarchy/gitea-workstatus/.collect.lock" 2>/dev/null || echo "")
  assert_eq "lock reclaimed from dead PID" "true" "$([ "$lock_content" != "999999" ] && echo true || echo false)"
else
  echo "  PASS: lock cleaned up after run"
  PASS=$((PASS + 1))
fi

rm -rf "$tmpdir"

# Test 6: Invoke collector with mock HTTP (curl wrapper)
echo "Test 6: Mocked collector execution"
mock_tmpdir=$(mktemp -d)
export XDG_STATE_HOME="$mock_tmpdir/state"
export XDG_CONFIG_HOME="$mock_tmpdir/config"
mkdir -p "$XDG_STATE_HOME/omarchy/gitea-workstatus" "$XDG_CONFIG_HOME/gitea-workstatus"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"

printf 'GITEA_URL="https://mock.test"\nGITEA_TOKEN="mock-token"\n' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"

# Create mock curl — strips all flags, matches URL pattern, returns canned JSON
# The real curl is called with -sfS or -sS plus -w, -H, --max-time etc.
# Our mock ignores all flags and just pattern-matches the URL argument.
cat > "$mock_tmpdir/curl" << MOCKCURL
#!/usr/bin/env bash
url=""
has_write_out=false
for arg in "\$@"; do
  case "\$arg" in
    https://*) url="\$arg" ;;
    *http_code*) has_write_out=true ;;
  esac
done

mock_dir="$MOCK_DIR"

# Match URL path (ignore query string for routing)
path=\$(echo "\$url" | grep -oP '/api/v1\K[^?]*')

case "\$path" in
  /user)
    cat "\$mock_dir/user.json"
    \$has_write_out && printf '\n200'
    ;;
  /user/repos)
    cat "\$mock_dir/repos.json"
    \$has_write_out && printf '\n200'
    ;;
  /repos/*/pulls)
    if echo "\$url" | grep -q "testuser/webapp"; then
      jq '[.[0], .[1]]' "\$mock_dir/pulls.json"
    else
      echo "[]"
    fi
    \$has_write_out && printf '\n200'
    ;;
  /repos/*/pulls/*/reviews)
    cat "\$mock_dir/reviews.json"
    \$has_write_out && printf '\n200'
    ;;
  /repos/*/commits/*/status)
    cat "\$mock_dir/commit-status-success.json"
    \$has_write_out && printf '\n200'
    ;;
  /repos/*/actions/runs)
    cat "\$mock_dir/action-runs.json"
    \$has_write_out && printf '\n200'
    ;;
  *)
    echo '[]'
    \$has_write_out && printf '\n200'
    ;;
esac
exit 0
MOCKCURL
chmod +x "$mock_tmpdir/curl"

PATH="$mock_tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

if [ -f "$mock_state" ]; then
  if jq empty "$mock_state" 2>/dev/null; then
    echo "  PASS: mocked collector produces valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: mocked collector output is not valid JSON"
    cat "$mock_state" | head -5
    FAIL=$((FAIL + 1))
  fi

  has_meta=$(jq 'has("meta")' "$mock_state" 2>/dev/null)
  assert_eq "mocked output has meta" "true" "$has_meta"

  has_summary=$(jq 'has("summary")' "$mock_state" 2>/dev/null)
  assert_eq "mocked output has summary" "true" "$has_summary"

  has_sections=$(jq 'has("sections")' "$mock_state" 2>/dev/null)
  assert_eq "mocked output has sections" "true" "$has_sections"

  pr_count=$(jq '.summary.open_prs // 0' "$mock_state" 2>/dev/null)
  assert_eq "mocked output has PRs" "true" "$([ "$pr_count" -gt 0 ] && echo true || echo false)"

  username=$(jq -r '.meta.username' "$mock_state" 2>/dev/null)
  assert_eq "mocked output has correct username" "testuser" "$username"

  assert_eq "mocked output not stale" "false" "$(jq '.meta.stale' "$mock_state" 2>/dev/null)"
else
  echo "  FAIL: mocked collector did not write output file"
  FAIL=$((FAIL + 1))
  # Skip remaining checks
  for i in 1 2 3 4 5; do
    echo "  FAIL: (skipped - no output)"
    FAIL=$((FAIL + 1))
  done
fi

rm -rf "$mock_tmpdir"

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
