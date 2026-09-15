#!/usr/bin/env bash
# Test the jq transform against mock data — no network or credentials needed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOCK_DIR="$SCRIPT_DIR/mock-responses"
JQ_SCRIPT="$SCRIPT_DIR/../bin/gitea-collect.jq"
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

assert_gt() {
  local desc="$1" threshold="$2" actual="$3"
  if [ "$actual" -gt "$threshold" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected > $threshold, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# Build mock PR data with embedded reviews and commit status
build_test_prs() {
  local prs reviews_approved reviews_changes status_ok status_fail

  prs=$(cat "$MOCK_DIR/pulls.json")
  reviews_approved=$(cat "$MOCK_DIR/reviews.json")
  reviews_changes=$(cat "$MOCK_DIR/reviews-changes.json")
  status_ok=$(cat "$MOCK_DIR/commit-status-success.json")
  status_fail=$(cat "$MOCK_DIR/commit-status-failure.json")

  # PR #42: approved reviews + successful CI
  # PR #43: changes requested + failed CI
  # PR #10: no reviews, no CI (draft)
  echo "$prs" | jq \
    --argjson rev_ok "$reviews_approved" \
    --argjson rev_chg "$reviews_changes" \
    --argjson ci_ok "$status_ok" \
    --argjson ci_fail "$status_fail" \
    '
    .[0]._reviews = $rev_ok | .[0]._commit_status = $ci_ok | .[0]._repo = "testuser/webapp" |
    .[1]._reviews = $rev_chg | .[1]._commit_status = $ci_fail | .[1]._repo = "testuser/webapp" |
    .[2]._reviews = [] | .[2]._commit_status = {} | .[2]._repo = "testuser/api-server"
    '
}

build_test_runs() {
  cat "$MOCK_DIR/action-runs.json" | jq '[.workflow_runs[] | . + {"_repo": "testuser/webapp"}]'
}

echo "=== Gitea Work Status: JQ Transform Tests ==="
echo ""

# --- Test 1: Basic structure ---
echo "Test 1: Output structure"

test_prs=$(build_test_prs)
test_runs=$(build_test_runs)

output=$(jq -n \
  --arg url "https://git.example.com" \
  --arg user "testuser" \
  --arg ts "2026-09-15T10:00:00Z" \
  --argjson prs "$test_prs" \
  --argjson runs "$test_runs" \
  --argjson repo_count 3 \
  --argjson max_stale 6 \
  -f "$JQ_SCRIPT")

assert_eq "has meta" "true" "$(echo "$output" | jq 'has("meta")')"
assert_eq "has summary" "true" "$(echo "$output" | jq 'has("summary")')"
assert_eq "has sections" "true" "$(echo "$output" | jq 'has("sections")')"
assert_eq "has repos" "true" "$(echo "$output" | jq 'has("repos")')"
assert_eq "meta.username" "testuser" "$(echo "$output" | jq -r '.meta.username')"
assert_eq "meta.gitea_url" "https://git.example.com" "$(echo "$output" | jq -r '.meta.gitea_url')"

echo ""

# --- Test 2: PR classification ---
echo "Test 2: PR classification"

pr42_status=$(echo "$output" | jq -r '.sections.all_prs[] | select(.id == 42) | .status_label')
pr43_status=$(echo "$output" | jq -r '.sections.all_prs[] | select(.id == 43) | .status_label')
pr10_status=$(echo "$output" | jq -r '.sections.all_prs[] | select(.id == 10) | .status_label')

assert_eq "PR #42 (approved + CI pass) = ready" "ready" "$pr42_status"
assert_eq "PR #43 (changes req + CI fail) = ci_failed" "ci_failed" "$pr43_status"
assert_eq "PR #10 (draft, no CI) = open" "open" "$pr10_status"

echo ""

# --- Test 3: Attention detection ---
echo "Test 3: Attention items"

attention_count=$(echo "$output" | jq '.sections.attention | length')
assert_gt "attention items exist" 0 "$attention_count"

pr43_attention=$(echo "$output" | jq '[.sections.attention[] | select(.id == 43)] | length')
assert_eq "PR #43 in attention (CI failed)" "1" "$pr43_attention"

echo ""

# --- Test 4: Blocker reasons ---
echo "Test 4: Blocker reasons"

pr43_blocker=$(echo "$output" | jq -r '.sections.all_prs[] | select(.id == 43) | .blocker')
assert_eq "PR #43 has blocker" "true" "$([ -n "$pr43_blocker" ] && [ "$pr43_blocker" != "null" ] && echo true || echo false)"

echo ""

# --- Test 5: Review summary ---
echo "Test 5: Review summaries"

pr42_approved=$(echo "$output" | jq '.sections.all_prs[] | select(.id == 42) | .reviews.approved')
pr43_changes=$(echo "$output" | jq '.sections.all_prs[] | select(.id == 43) | .reviews.changes_requested')

assert_eq "PR #42 approved count" "1" "$pr42_approved"
assert_eq "PR #43 changes_requested count" "1" "$pr43_changes"

echo ""

# --- Test 6: CI summary ---
echo "Test 6: CI summaries"

pr42_ci_passed=$(echo "$output" | jq '.sections.all_prs[] | select(.id == 42) | .ci.passed')
pr42_ci_total=$(echo "$output" | jq '.sections.all_prs[] | select(.id == 42) | .ci.total')
pr43_ci_failed=$(echo "$output" | jq '.sections.all_prs[] | select(.id == 43) | .ci.failed')

assert_eq "PR #42 CI passed" "3" "$pr42_ci_passed"
assert_eq "PR #42 CI total" "3" "$pr42_ci_total"
assert_eq "PR #43 CI failed" "1" "$pr43_ci_failed"

echo ""

# --- Test 7: Job categorization ---
echo "Test 7: Job buckets"

running_count=$(echo "$output" | jq '.sections.running | length')
completed_count=$(echo "$output" | jq '.sections.recently_completed | length')

assert_eq "running jobs" "1" "$running_count"
assert_eq "recently completed (success + failure)" "2" "$completed_count"

echo ""

# --- Test 8: Summary counts ---
echo "Test 8: Summary aggregation"

summary_open=$(echo "$output" | jq '.summary.open_prs')
summary_attention=$(echo "$output" | jq '.summary.needs_attention')
summary_running=$(echo "$output" | jq '.summary.running_jobs')

assert_eq "open PRs" "3" "$summary_open"
assert_gt "attention count" 0 "$summary_attention"
assert_eq "running jobs" "1" "$summary_running"

echo ""

# --- Test 9: My PRs ---
echo "Test 9: My PRs section"

my_prs=$(echo "$output" | jq '.sections.my_prs | length')
assert_eq "my PRs count (testuser authored)" "2" "$my_prs"

echo ""

# --- Test 10: Review queue ---
echo "Test 10: Review queue"

review_queue=$(echo "$output" | jq '.sections.review_queue | length')
assert_eq "review queue (requested for testuser)" "1" "$review_queue"

review_pr=$(echo "$output" | jq -r '.sections.review_queue[0].id')
assert_eq "review queue PR is #43" "43" "$review_pr"

echo ""

# --- Test 11: Repos list ---
echo "Test 11: Repos enumeration"

repos_count=$(echo "$output" | jq '.repos | length')
assert_eq "unique repos" "2" "$repos_count"

echo ""

# === Summary ===
echo "==========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "==========================================="

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
