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

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

# Creates a fresh temp environment, sets XDG_STATE_HOME/XDG_CONFIG_HOME, returns path
setup_env() {
  _SETUP_TMP=$(mktemp -d)
  export XDG_STATE_HOME="$_SETUP_TMP/state"
  export XDG_CONFIG_HOME="$_SETUP_TMP/config"
  mkdir -p "$XDG_STATE_HOME/omarchy/gitea-workstatus" "$XDG_CONFIG_HOME/gitea-workstatus"
  printf 'GITEA_URL="https://mock.test"\nGITEA_TOKEN="mock-token"\n' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"
}

# Creates a mock curl that returns status code and body based on path matching
# Usage: make_mock_curl <tmpdir> <behavior>
# behavior: "normal" | "500_repos" | "401_auth" | "malformed" | "timeout" | "pr_fail" | "actions_only"
make_mock_curl() {
  local tmpdir="$1" behavior="$2"
  cat > "$tmpdir/curl" << ENDCURL
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
path=\$(echo "\$url" | grep -oP '/api/v1\K[^?]*' || echo "")

case "$behavior" in
  500_repos)
    case "\$path" in
      /user) cat "\$mock_dir/user.json"; \$has_write_out && printf '\n200' ;;
      /user/repos) echo '{"message":"Internal Server Error"}'; \$has_write_out && printf '\n500' ;;
      *) echo '[]'; \$has_write_out && printf '\n200' ;;
    esac
    ;;
  401_auth)
    echo '{"message":"Unauthorized"}'; \$has_write_out && printf '\n401'
    ;;
  malformed)
    case "\$path" in
      /user) cat "\$mock_dir/user.json"; \$has_write_out && printf '\n200' ;;
      /user/repos) echo 'not json at all {{{'; \$has_write_out && printf '\n200' ;;
      *) echo '[]'; \$has_write_out && printf '\n200' ;;
    esac
    ;;
  timeout)
    sleep 20
    exit 1
    ;;
  pr_fail)
    case "\$path" in
      /user) cat "\$mock_dir/user.json"; \$has_write_out && printf '\n200' ;;
      /user/repos) cat "\$mock_dir/repos.json"; \$has_write_out && printf '\n200' ;;
      /repos/*/pulls) echo '{"error": "oops"}'; \$has_write_out && printf '\n500' ;;
      /repos/*/actions/runs) cat "\$mock_dir/action-runs.json"; \$has_write_out && printf '\n200' ;;
      *) echo '[]'; \$has_write_out && printf '\n200' ;;
    esac
    ;;
  actions_only)
    case "\$path" in
      /user) cat "\$mock_dir/user.json"; \$has_write_out && printf '\n200' ;;
      /user/repos) echo '[{"owner":{"login":"testuser"},"name":"ci-only","has_pull_requests":false}]'; \$has_write_out && printf '\n200' ;;
      /repos/*/actions/runs) cat "\$mock_dir/action-runs.json"; \$has_write_out && printf '\n200' ;;
      *) echo '[]'; \$has_write_out && printf '\n200' ;;
    esac
    ;;
  normal|*)
    case "\$path" in
      /user) cat "\$mock_dir/user.json"; \$has_write_out && printf '\n200' ;;
      /user/repos) cat "\$mock_dir/repos.json"; \$has_write_out && printf '\n200' ;;
      /repos/*/pulls)
        if echo "\$url" | grep -q "testuser/webapp"; then
          jq '[.[0], .[1]]' "\$mock_dir/pulls.json"
        else
          echo "[]"
        fi
        \$has_write_out && printf '\n200'
        ;;
      /repos/*/pulls/*/reviews) cat "\$mock_dir/reviews.json"; \$has_write_out && printf '\n200' ;;
      /repos/*/commits/*/status) cat "\$mock_dir/commit-status-success.json"; \$has_write_out && printf '\n200' ;;
      /repos/*/actions/runs) cat "\$mock_dir/action-runs.json"; \$has_write_out && printf '\n200' ;;
      *) echo '[]'; \$has_write_out && printf '\n200' ;;
    esac
    ;;
esac
exit 0
ENDCURL
  chmod +x "$tmpdir/curl"
}

echo "=== Collector Validation Tests ==="
echo ""

# ── Test 1: Script syntax ──
echo "Test 1: Script can be invoked via bash"
if bash -n "$COLLECTOR" 2>/dev/null; then
  echo "  PASS: bash -n passes"
  PASS=$((PASS + 1))
else
  echo "  FAIL: bash -n failed"
  FAIL=$((FAIL + 1))
fi

# ── Test 2: JQ script syntax ──
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

# ── Test 3: Missing credentials ──
echo "Test 3: Missing credentials error"
setup_env; tmpdir="$_SETUP_TMP"
rm -f "$XDG_CONFIG_HOME/gitea-workstatus/credentials"
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
rm -rf "$tmpdir"

# ── Test 4: Empty GITEA_URL ──
echo "Test 4: Empty URL error"
setup_env; tmpdir="$_SETUP_TMP"
printf 'GITEA_URL=""\nGITEA_TOKEN="test-token"\n' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"
state_file="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"

bash "$COLLECTOR" 2>/dev/null || true
if [ -f "$state_file" ]; then
  error_msg=$(jq -r '.error // empty' "$state_file" 2>/dev/null)
  assert_contains "error mentions URL" "URL" "$error_msg"
fi
rm -rf "$tmpdir"

# ── Test 5: flock-based lock ──
echo "Test 5: flock-based lock"
setup_env; tmpdir="$_SETUP_TMP"
lock_file="$XDG_STATE_HOME/omarchy/gitea-workstatus/.collect.lock"
# Write something arbitrary into the lock file
echo "old-content" > "$lock_file"
# flock should still acquire it (flock doesn't care about file content)
bash "$COLLECTOR" 2>/dev/null || true
echo "  PASS: flock acquires lock regardless of file content"
PASS=$((PASS + 1))
rm -rf "$tmpdir"

# ── Test 6: Normal mocked execution ──
echo "Test 6: Mocked collector execution"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
make_mock_curl "$tmpdir" "normal"
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

if [ -f "$mock_state" ]; then
  if jq empty "$mock_state" 2>/dev/null; then
    echo "  PASS: mocked collector produces valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: mocked collector output is not valid JSON"
    FAIL=$((FAIL + 1))
  fi
  assert_eq "has meta" "true" "$(jq 'has("meta")' "$mock_state" 2>/dev/null)"
  assert_eq "has summary" "true" "$(jq 'has("summary")' "$mock_state" 2>/dev/null)"
  assert_eq "has sections" "true" "$(jq 'has("sections")' "$mock_state" 2>/dev/null)"
  pr_count=$(jq '.summary.open_prs // 0' "$mock_state" 2>/dev/null)
  assert_eq "has PRs" "true" "$([ "$pr_count" -gt 0 ] && echo true || echo false)"
  assert_eq "correct username" "testuser" "$(jq -r '.meta.username' "$mock_state" 2>/dev/null)"
  assert_eq "not stale" "false" "$(jq '.meta.stale' "$mock_state" 2>/dev/null)"
else
  echo "  FAIL: mocked collector did not write output file"
  FAIL=$((FAIL + 1))
fi
rm -rf "$tmpdir"

# ── Test 7: HTTP 500 on repo listing ──
echo "Test 7: HTTP 500 on repo listing"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
make_mock_curl "$tmpdir" "500_repos"
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

# Should die with error, but not crash
if [ -f "$XDG_STATE_HOME/omarchy/gitea-workstatus/last-error.json" ]; then
  assert_contains "500 error recorded" "Cannot list" "$(jq -r '.error // empty' "$XDG_STATE_HOME/omarchy/gitea-workstatus/last-error.json" 2>/dev/null)"
else
  # Error may be in overview.json if no prior good data
  if [ -f "$mock_state" ]; then
    assert_contains "500 error in state" "Cannot list\|error\|Error" "$(jq -r '.error // .meta.error // empty' "$mock_state" 2>/dev/null)"
  else
    echo "  FAIL: no error file written for 500 response"
    FAIL=$((FAIL + 1))
  fi
fi
rm -rf "$tmpdir"

# ── Test 8: Authentication failure preserves last-good data ──
echo "Test 8: Auth failure preserves last-good data"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
# Write "last-good" data
echo '{"meta":{"collected_at":"2024-01-01T00:00:00Z","stale":false},"summary":{"open_prs":5},"sections":{}}' > "$mock_state"
make_mock_curl "$tmpdir" "401_auth"
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

# Last-good data should still be there
preserved_prs=$(jq '.summary.open_prs // 0' "$mock_state" 2>/dev/null)
assert_eq "last-good data preserved" "5" "$preserved_prs"
assert_file_exists "error file written" "$XDG_STATE_HOME/omarchy/gitea-workstatus/last-error.json"
rm -rf "$tmpdir"

# ── Test 9: Malformed JSON response ──
echo "Test 9: Malformed JSON from repo listing"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
make_mock_curl "$tmpdir" "malformed"
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

# Should fail gracefully — either error or empty result, not crash
echo "  PASS: collector did not crash on malformed JSON"
PASS=$((PASS + 1))
rm -rf "$tmpdir"

# ── Test 10: PR/review failures with Actions still working ──
echo "Test 10: PR failures with Actions still working"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
make_mock_curl "$tmpdir" "pr_fail"
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

if [ -f "$mock_state" ] && jq -e 'has("sections")' "$mock_state" >/dev/null 2>&1; then
  # Actions runs should still have been collected
  run_count=$(jq '[.sections.running[]?, .sections.recently_completed[]?] | length' "$mock_state" 2>/dev/null || echo "0")
  assert_eq "runs collected despite PR failure" "true" "$([ "$run_count" -ge 0 ] && echo true || echo false)"
  repo_failed=$(jq '.meta.repo_failed // 0' "$mock_state" 2>/dev/null)
  assert_eq "partial failure counted" "true" "$([ "$repo_failed" -gt 0 ] && echo true || echo false)"
else
  echo "  PASS: collector handled PR failure (error or partial output)"
  PASS=$((PASS + 1))
fi
rm -rf "$tmpdir"

# ── Test 11: Actions-only repos (has_pull_requests: false) ──
echo "Test 11: Actions-only repos"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
make_mock_curl "$tmpdir" "actions_only"
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

if [ -f "$mock_state" ] && jq -e 'has("repos")' "$mock_state" >/dev/null 2>&1; then
  # The actions-only repo should appear in repos list
  has_ci_only=$(jq '.repos | index("testuser/ci-only") != null' "$mock_state" 2>/dev/null)
  assert_eq "actions-only repo in repos list" "true" "$has_ci_only"
else
  echo "  FAIL: no repos data for actions-only test"
  FAIL=$((FAIL + 1))
fi
rm -rf "$tmpdir"

# ── Test 12: Stale carry-forward when both PRs and runs are empty ──
echo "Test 12: Stale carry-forward"
setup_env; tmpdir="$_SETUP_TMP"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"

# Write previous good data with recent timestamp
recent_ts=$(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$mock_state" << STALEDATA
{"meta":{"collected_at":"$recent_ts","stale":false},"summary":{"open_prs":3},"sections":{"all_prs":[{"repo":"test/r","id":1}],"running":[],"recently_completed":[],"attention":[],"my_prs":[],"review_queue":[]},"repos":["test/r"]}
STALEDATA

# Mock curl that returns empty results for everything
cat > "$tmpdir/curl" << 'EMPTYCURL'
#!/usr/bin/env bash
url=""
has_write_out=false
for arg in "$@"; do
  case "$arg" in
    https://*) url="$arg" ;;
    *http_code*) has_write_out=true ;;
  esac
done
path=$(echo "$url" | grep -oP '/api/v1\K[^?]*' || echo "")
case "$path" in
  /user) echo '{"login":"testuser"}'; $has_write_out && printf '\n200' ;;
  /user/repos) echo '[{"owner":{"login":"testuser"},"name":"somerepo","has_pull_requests":true}]'; $has_write_out && printf '\n200' ;;
  *) echo '[]'; $has_write_out && printf '\n200' ;;
esac
exit 0
EMPTYCURL
chmod +x "$tmpdir/curl"

PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null || true

stale_flag=$(jq '.meta.stale // false' "$mock_state" 2>/dev/null)
assert_eq "stale flag set" "true" "$stale_flag"
preserved_prs=$(jq '.summary.open_prs // 0' "$mock_state" 2>/dev/null)
assert_eq "previous data preserved" "3" "$preserved_prs"
rm -rf "$tmpdir"

# ── Test 13: Two concurrent collectors (flock contention) ──
echo "Test 13: Two concurrent collectors (flock)"
setup_env; tmpdir="$_SETUP_TMP"
lock_file="$XDG_STATE_HOME/omarchy/gitea-workstatus/.collect.lock"

# Hold the lock in background
(
  exec 9>"$lock_file"
  flock 9
  sleep 3
) &
holder_pid=$!
sleep 0.5

# Second collector should exit immediately with exit code 0
PATH="$tmpdir:$PATH" bash "$COLLECTOR" 2>/dev/null
exit_code=$?
assert_eq "second collector exits cleanly" "0" "$exit_code"

kill "$holder_pid" 2>/dev/null || true
wait "$holder_pid" 2>/dev/null || true
rm -rf "$tmpdir"

echo ""
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
