# gitea-collect.jq — Transform raw API data into the overview structure
# Input: --arg url, --arg user, --arg ts, --argjson prs, --argjson runs, --argjson repo_count, --argjson max_stale

def review_summary:
  if type == "array" then
    {
      approved: [.[] | select(.state == "APPROVED")] | length,
      changes_requested: [.[] | select(.state == "REQUEST_CHANGES" or .state == "CHANGES_REQUESTED")] | length,
      commented: [.[] | select(.state == "COMMENT")] | length,
      pending: [.[] | select(.state == "PENDING")] | length,
      dismissed: [.[] | select(.state == "DISMISSED")] | length,
      reviewers: [.[] | .user.login] | unique
    }
  else
    { approved: 0, changes_requested: 0, commented: 0, pending: 0, dismissed: 0, reviewers: [] }
  end;

def ci_summary:
  if type == "object" and .statuses then
    {
      state: (.state // "unknown"),
      total: (.total_count // 0),
      checks: [(.statuses // [])[] | {
        context: .context,
        state: .status,
        description: .description,
        target_url: .target_url,
        created: .created_at
      }],
      passed: [(.statuses // [])[] | select(.status == "success")] | length,
      failed: [(.statuses // [])[] | select(.status == "failure" or .status == "error")] | length,
      pending_count: [(.statuses // [])[] | select(.status == "pending")] | length
    }
  else
    { state: "unknown", total: 0, checks: [], passed: 0, failed: 0, pending_count: 0 }
  end;

def pr_attention($user):
  .reviews.changes_requested > 0
  or (.ci.state == "failure" or .ci.state == "error")
  or (.requested_reviewers // [] | index($user) != null);

def pr_status_label($user):
  if .ci.state == "failure" or .ci.state == "error" then "ci_failed"
  elif .reviews.changes_requested > 0 then "changes_requested"
  elif (.requested_reviewers // [] | index($user) != null) then "review_requested"
  elif .ci.state == "pending" and .ci.total > 0 then "ci_running"
  elif .reviews.approved > 0 and .ci.state == "success" then "ready"
  elif .reviews.approved > 0 then "approved"
  elif .ci.state == "success" then "ci_passed"
  else "open"
  end;

def blocker_reason($user):
  [
    (if .ci.failed > 0 then
      (.ci.checks | map(select(.state == "failure" or .state == "error")) | map(.context) | join(", "))
      | if . != "" then "CI failed: " + . else empty end
    else empty end),
    (if .reviews.changes_requested > 0 then
      "Changes requested by reviewer"
    else empty end),
    (if (.mergeable // true) == false then
      "Merge conflicts"
    else empty end),
    (if .reviews.approved == 0 and (.requested_reviewers // [] | length) > 0 then
      "Awaiting review"
    else empty end)
  ] | if length > 0 then join("; ") else null end;

def run_status_bucket:
  if .status == "running" or .status == "waiting" then "running"
  elif .status == "success" then "completed"
  elif .status == "failure" or .status == "cancelled" then "failed"
  else "other"
  end;

# Transform PRs
($prs | map({
  id: .number,
  repo: ._repo,
  title: .title,
  branch: .head.ref,
  base: .base.ref,
  author: .user.login,
  author_avatar: .user.avatar_url,
  created: .created_at,
  updated: .updated_at,
  url: .html_url,
  mergeable: .mergeable,
  draft: (.draft // false),
  labels: [(.labels // [])[] | { name: .name, color: .color }],
  requested_reviewers: [(.requested_reviewers // [])[] | .login],
  reviews: (._reviews | review_summary),
  ci: (._commit_status | ci_summary),
  head_sha: .head.sha
})) as $processed_prs |

# Classify each PR
($processed_prs | map(
  . + {
    status_label: pr_status_label($user),
    needs_attention: pr_attention($user),
    blocker: blocker_reason($user)
  }
)) as $classified_prs |

# Transform runs
($runs | map({
  id: .id,
  repo: ._repo,
  workflow: .name,
  status: .status,
  conclusion: .conclusion,
  branch: .head_branch,
  event: .event,
  started: .created_at,
  updated: .updated_at,
  url: .html_url,
  bucket: run_status_bucket
})) as $processed_runs |

# Build categorized buckets
{
  meta: {
    gitea_url: $url,
    username: $user,
    collected_at: $ts,
    repo_count: $repo_count,
    stale: false,
    max_stale_hours: $max_stale
  },
  summary: {
    needs_attention: [$classified_prs[] | select(.needs_attention)] | length,
    review_requested: [$classified_prs[] | select(.status_label == "review_requested")] | length,
    ci_failed: [$classified_prs[] | select(.status_label == "ci_failed")] | length,
    changes_requested: [$classified_prs[] | select(.status_label == "changes_requested")] | length,
    running_jobs: [$processed_runs[] | select(.bucket == "running")] | length,
    open_prs: ($classified_prs | length),
    ready_to_merge: [$classified_prs[] | select(.status_label == "ready")] | length
  },
  sections: {
    attention: [$classified_prs[] | select(.needs_attention)] | sort_by(.updated) | reverse,
    running: [$processed_runs[] | select(.bucket == "running")] | sort_by(.updated) | reverse,
    recently_completed: (
      ([$processed_runs[] | select(.bucket == "completed" or .bucket == "failed")]
       | sort_by(.updated) | reverse | .[0:20])
    ),
    my_prs: [$classified_prs[] | select(.author == $user)] | sort_by(.updated) | reverse,
    review_queue: [$classified_prs[] | select(
      .requested_reviewers | index($user) != null
    )] | sort_by(.updated) | reverse,
    all_prs: $classified_prs | sort_by(.updated) | reverse
  },
  repos: ($classified_prs | map(.repo) | unique | sort)
}
