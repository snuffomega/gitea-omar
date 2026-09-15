#!/usr/bin/env bash
# Test Model.js logic via Node.js — no QML runtime needed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOCK_DIR="$SCRIPT_DIR/mock-responses"
JQ_SCRIPT="$SCRIPT_DIR/../bin/gitea-collect.jq"

# Generate the overview JSON using the jq transform
build_test_prs() {
  local prs reviews_approved reviews_changes status_ok status_fail
  prs=$(cat "$MOCK_DIR/pulls.json")
  reviews_approved=$(cat "$MOCK_DIR/reviews.json")
  reviews_changes=$(cat "$MOCK_DIR/reviews-changes.json")
  status_ok=$(cat "$MOCK_DIR/commit-status-success.json")
  status_fail=$(cat "$MOCK_DIR/commit-status-failure.json")

  echo "$prs" | jq \
    --argjson rev_ok "$reviews_approved" \
    --argjson rev_chg "$reviews_changes" \
    --argjson ci_ok "$status_ok" \
    --argjson ci_fail "$status_fail" \
    '
    .[0]._reviews = $rev_ok | .[0]._commit_status = $ci_ok | .[0]._repo = "testuser/webapp" |
    .[1]._reviews = $rev_chg | .[1]._commit_status = $ci_fail | .[1]._repo = "testuser/webapp" |
    .[2]._reviews = [] | .[2]._commit_status = {} | .[2]._repo = "testuser/api-server" |
    .[3]._reviews = [] | .[3]._commit_status = {} | .[3]._repo = "testuser/webapp" |
    .[4]._reviews = [] | .[4]._commit_status = {} | .[4]._repo = "testuser/webapp"
    '
}

build_test_runs() {
  cat "$MOCK_DIR/action-runs.json" | jq '[.workflow_runs[] | . + {"_repo": "testuser/webapp"}]'
}

test_prs=$(build_test_prs)
test_runs=$(build_test_runs)

overview=$(jq -n \
  --arg url "https://git.example.com" \
  --arg user "testuser" \
  --arg ts "2026-09-15T10:00:00Z" \
  --argjson prs "$test_prs" \
  --argjson runs "$test_runs" \
  --argjson repo_count 3 \
  --argjson max_stale 6 \
  --argjson repo_failed 0 \
  --argjson repo_attempted 3 \
  --argjson incomplete false \
  -f "$JQ_SCRIPT")

overview_json=$(echo "$overview" | jq -c .)

# Build a second overview where PR #43's CI is now fixed (for notification transition test)
overview2_prs=$(echo "$test_prs" | jq \
  --argjson ci_ok "$(cat "$MOCK_DIR/commit-status-success.json")" \
  '.[1]._commit_status = $ci_ok')
overview2=$(jq -n \
  --arg url "https://git.example.com" \
  --arg user "testuser" \
  --arg ts "2026-09-15T10:05:00Z" \
  --argjson prs "$overview2_prs" \
  --argjson runs "$test_runs" \
  --argjson repo_count 3 \
  --argjson max_stale 6 \
  --argjson repo_failed 0 \
  --argjson repo_attempted 3 \
  --argjson incomplete false \
  -f "$JQ_SCRIPT")
overview2_json=$(echo "$overview2" | jq -c .)

# Build a third overview where a NEW PR (#99) has CI failure (total count = 1 again)
overview3_prs=$(echo "$overview2_prs" | jq '. + [{
  "number": 99, "title": "New broken PR", "state": "open", "draft": false,
  "user": {"login": "someone"}, "head": {"ref": "broken", "sha": "zzz"},
  "base": {"ref": "main"}, "created_at": "2026-09-15T10:06:00Z",
  "updated_at": "2026-09-15T10:06:00Z", "html_url": "https://git.example.com/testuser/webapp/pulls/99",
  "mergeable": true, "labels": [], "requested_reviewers": [],
  "_reviews": [{"id": 99, "user": {"login": "x"}, "state": "REQUEST_CHANGES", "submitted_at": "2026-09-15T10:06:00Z"}],
  "_commit_status": {"state": "failure", "total_count": 1, "statuses": [{"context": "ci/build", "status": "failure", "description": "Build failed", "target_url": "", "created_at": "2026-09-15T10:06:00Z"}]},
  "_repo": "testuser/webapp"
}]')
overview3=$(jq -n \
  --arg url "https://git.example.com" \
  --arg user "testuser" \
  --arg ts "2026-09-15T10:10:00Z" \
  --argjson prs "$overview3_prs" \
  --argjson runs "$test_runs" \
  --argjson repo_count 3 \
  --argjson max_stale 6 \
  --argjson repo_failed 0 \
  --argjson repo_attempted 3 \
  --argjson incomplete false \
  -f "$JQ_SCRIPT")
overview3_json=$(echo "$overview3" | jq -c .)

node <<NODETEST
const fs = require('fs');

const modelSrc = fs.readFileSync('$SCRIPT_DIR/../Model.js', 'utf-8')
  .replace('.pragma library', '');
eval(modelSrc);

let pass = 0, fail = 0;

function assert(desc, expected, actual) {
  if (expected === actual) { console.log("  PASS: " + desc); pass++; }
  else { console.log("  FAIL: " + desc + " (expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual) + ")"); fail++; }
}

console.log("=== Model.js Unit Tests ===");
console.log("");

// --- Test: parseOverview ---
console.log("Test: parseOverview");
assert("parseOverview succeeds", true, parseOverview(JSON.stringify($overview_json)));
assert("getData not null", true, getData() !== null);
assert("revision incremented", true, revision() > 0);

console.log("");
console.log("Test: getBarSummary (unfiltered)");
const bar = getBarSummary();
assert("bar.total", 5, bar.total);
assert("bar.attention > 0", true, bar.attention > 0);
assert("bar.running", 1, bar.running);
assert("bar.healthy is false", false, bar.healthy);

console.log("");
console.log("Test: Section filters");
setSectionFilter("attention");
const attention = getActiveSection();
assert("attention has items", true, attention.length > 0);

setSectionFilter("my_prs");
const myPrs = getActiveSection();
assert("my_prs count", 4, myPrs.length);

console.log("");
console.log("Test: Repo filter");
setRepoFilter("testuser/webapp");
setSectionFilter("all");
const filtered = getActiveSection();
assert("filtered to webapp", true, filtered.every(p => p.repo === "testuser/webapp"));
assert("filtered count", 4, filtered.length);

setRepoFilter("");
const unfiltered = getActiveSection();
assert("unfiltered count", 5, unfiltered.length);

console.log("");
console.log("Test: Muted repos applied to bar summary");
setMutedRepos("testuser/api-server");
assert("api-server is muted", true, isMuted("testuser/api-server"));
assert("webapp is not muted", false, isMuted("testuser/webapp"));

const barAfterMute = getBarSummary();
assert("muted repo excluded from bar total", 4, barAfterMute.total);

setSectionFilter("all");
const afterMute = getActiveSection();
assert("muted repo excluded from sections", true, afterMute.every(p => p.repo !== "testuser/api-server"));

setMutedRepos("");

console.log("");
console.log("Test: Cold-start notification suppression");
// First call after parseOverview: cold start — no notifications
const notesCold = getNewNotifications(true, true);
assert("cold start: zero notifications", 0, notesCold.length);

console.log("");
console.log("Test: Notifications do NOT repeat for same state (post cold-start)");
// Second call with same data: state already seeded by cold start — still zero
const notes1b = getNewNotifications(true, true);
assert("repeat: no duplicate CI notification", 0, notes1b.filter(n => n.type === "failure").length);
assert("repeat: no duplicate review notification", 0, notes1b.filter(n => n.type === "review").length);

console.log("");
console.log("Test: Notification on transition (PR fixes, new PR breaks)");
// Load overview2 where PR #43 CI is now fixed
parseOverview(JSON.stringify($overview2_json));
const notes2 = getNewNotifications(true, true);
// PR #43 moved from ci_failed -> not failed, so no new failure for it
assert("transition: no CI notification for fixed PR", 0, notes2.filter(n => n.type === "failure").length);

// Now load overview3 where a NEW PR #99 has CI failure
parseOverview(JSON.stringify($overview3_json));
const notes3 = getNewNotifications(true, true);
const newFailNotes = notes3.filter(n => n.type === "failure");
assert("new PR failure: fires notification", true, newFailNotes.length > 0);
assert("new PR failure: mentions PR 99", true, newFailNotes.some(n => n.message.indexOf("#99") !== -1 || n.message.indexOf("broken") !== -1));

console.log("");
console.log("Test: Muted repos excluded from notifications");
parseOverview(JSON.stringify($overview_json));
// Clear notify state for clean test
_notifyState = {};
setMutedRepos("testuser/webapp");
const mutedNotes = getNewNotifications(true, true);
assert("muted: no notifications for muted repo", 0, mutedNotes.length);
setMutedRepos("");

console.log("");
console.log("Test: timeAgo");
assert("null input", "", timeAgo(null));
assert("empty input", "", timeAgo(""));

console.log("");
console.log("Test: statusIcon coverage");
assert("ci_failed icon", "\u2718", statusIcon("ci_failed"));
assert("approved_ci_passed icon", "\u2714", statusIcon("approved_ci_passed"));
assert("draft icon", "\u25CC", statusIcon("draft"));
assert("conflicted icon", "\u26A0", statusIcon("conflicted"));

console.log("");
console.log("===========================================");
console.log("Results: " + pass + " passed, " + fail + " failed");
console.log("===========================================");

process.exit(fail > 0 ? 1 : 0);
NODETEST
