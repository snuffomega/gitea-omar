#!/usr/bin/env bash
# Test Model.js logic via Node.js — no QML runtime needed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOCK_DIR="$SCRIPT_DIR/mock-responses"
JQ_SCRIPT="$SCRIPT_DIR/../bin/gitea-collect.jq"

# First generate the overview JSON using the same jq transform
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
    .[2]._reviews = [] | .[2]._commit_status = {} | .[2]._repo = "testuser/api-server"
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
  -f "$JQ_SCRIPT")

# Test Model.js through Node.js
node <<NODETEST
const fs = require('fs');

// Load Model.js and strip the .pragma library directive
const modelSrc = fs.readFileSync('$SCRIPT_DIR/../Model.js', 'utf-8')
  .replace('.pragma library', '');
eval(modelSrc);

const overview = JSON.parse('$(echo "$overview" | jq -c .)');
let pass = 0, fail = 0;

function assert(desc, expected, actual) {
  if (expected === actual) { console.log("  PASS: " + desc); pass++; }
  else { console.log("  FAIL: " + desc + " (expected " + expected + ", got " + actual + ")"); fail++; }
}

console.log("=== Model.js Unit Tests ===");
console.log("");

// Parse
console.log("Test: parseOverview");
assert("parseOverview succeeds", true, parseOverview(JSON.stringify(overview)));
assert("getData not null", true, getData() !== null);

console.log("");
console.log("Test: getBarSummary");
const bar = getBarSummary();
assert("bar.total", 3, bar.total);
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
assert("my_prs count", 2, myPrs.length);

console.log("");
console.log("Test: Repo filter");
setRepoFilter("testuser/webapp");
setSectionFilter("all");
const filtered = getActiveSection();
assert("filtered to webapp", true, filtered.every(p => p.repo === "testuser/webapp"));
assert("filtered count", 2, filtered.length);

setRepoFilter("");
const unfiltered = getActiveSection();
assert("unfiltered count", 3, unfiltered.length);

console.log("");
console.log("Test: Muted repos");
setMutedRepos("testuser/api-server");
assert("api-server is muted", true, isMuted("testuser/api-server"));
assert("webapp is not muted", false, isMuted("testuser/webapp"));

setSectionFilter("all");
const afterMute = getActiveSection();
assert("muted repo excluded", true, afterMute.every(p => p.repo !== "testuser/api-server"));

setMutedRepos("");

console.log("");
console.log("Test: timeAgo");
assert("null input", "", timeAgo(null));
assert("empty input", "", timeAgo(""));

console.log("");
console.log("Test: statusIcon");
assert("ci_failed icon", "\u2718", statusIcon("ci_failed"));
assert("ready icon", "\u2714", statusIcon("ready"));

console.log("");
console.log("Test: Notification dedup");
assert("first notify", true, shouldNotify("test_key"));
assert("second notify (deduped)", false, shouldNotify("test_key"));
assert("different key", true, shouldNotify("other_key"));

console.log("");
console.log("===========================================");
console.log("Results: " + pass + " passed, " + fail + " failed");
console.log("===========================================");

process.exit(fail > 0 ? 1 : 0);
NODETEST
