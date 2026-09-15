# gitea.workstatus — Gitea Work Status for Omarchy 4

A native Omarchy shell bar widget that monitors your self-hosted Gitea instance:
open PRs, review requests, CI status, and running jobs — all in one glance.

**Requires Gitea >= 1.19.** Actions/CI monitoring requires Gitea >= 1.20.

## Features

- **Compact bar summary**: failed CI, pending reviews, running jobs — color-coded,
  pulsing when active, quiet when healthy
- **Prioritized panel**: Attention → Running → Completed → My PRs → Review Queue
- **Blocker explanations**: passing CI alone does not mean ready to merge — the
  plugin checks approvals, merge conflicts, draft status, and mergeability
- **Latest review per reviewer**: if a reviewer requests changes then later
  approves, only the latest review counts
- **One-click navigation**: open any PR, failed job, or repository directly
- **Repo filtering**: focus on one repo, or mute repos you do not care about
  (muted repos are excluded from counts and notifications)
- **Keyboard-driven**: j/k navigate, h/l switch sections, Enter opens, r refreshes
- **Identity-based notifications**: alerts fire on status transitions per PR/run,
  not aggregate counts — a PR that stays failed does not re-alert, but a new
  failure always does even if the total count stays the same
- **Stale data carry-forward**: if connectivity drops, last good data is preserved
  (marked stale) for up to `maxStaleHours`
- **Atomic writes**: output JSON is written atomically via temp+rename
- **Ownership-safe locking**: the lock file tracks its owner PID; a skipped
  invocation never removes another collector's lock

## Runtime dependencies

| Dependency | Purpose | Provided by Omarchy |
|------------|---------|---------------------|
| `bash` | Collector script | Yes |
| `curl` | Gitea API calls | Yes |
| `jq` (>= 1.6) | JSON transforms | Yes |
| `coreutils` (`mktemp`, `stat`, `date`, `base64`) | Utilities | Yes |
| Quickshell | QML runtime | Yes (omarchy-shell) |

No additional packages need to be installed on a standard Omarchy 4 system.

## Install

### 1. Copy into your plugins directory

```bash
mkdir -p ~/.config/omarchy/plugins
cp -r gitea-workstatus ~/.config/omarchy/plugins/gitea.workstatus
```

### 2. Create credentials

```bash
mkdir -p ~/.config/gitea-workstatus

cat > ~/.config/gitea-workstatus/credentials << 'EOF'
GITEA_URL="https://git.example.com"
GITEA_TOKEN="your-gitea-api-token"
EOF

chmod 600 ~/.config/gitea-workstatus/credentials
```

Generate a token at `https://your-gitea/user/settings/applications` with
read-only scopes: `read:issue`, `read:repository`, `read:user`.

### 3. Enable the plugin

```bash
omarchy plugin enable gitea.workstatus
```

Or force discovery:

```bash
omarchy-shell shell rescanPlugins
```

## Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `refreshIntervalSec` | integer | 180 | Poll interval (seconds) |
| `giteaUrl` | string | — | Gitea instance URL |
| `maxStaleHours` | integer | 6 | Hours before stale data is hidden |
| `notifyOnFailure` | boolean | true | Notify on CI failure |
| `notifyOnReviewRequest` | boolean | true | Notify on review request |
| `mutedRepos` | string | — | Comma-separated `owner/repo` to exclude |

## Bar Widget

Color-coded compact indicators:

| Indicator | Meaning |
|-----------|---------|
| Red `✘ N` | N PRs with failed CI |
| Blue `● N` | N PRs awaiting your review |
| Amber `◦ N` (pulsing) | N jobs running |
| Green `✔ N` | N PRs ready to merge |

When everything is healthy, the icon is subdued. `!` appears on error.

## Panel Sections

| Section | Shows |
|---------|-------|
| Attention | PRs with failed CI, requested changes, or your review needed |
| Running | Active CI/CD jobs |
| Completed | Recent job results (success and failure) |
| My PRs | PRs you authored |
| Review | PRs where you are a requested reviewer |
| All | Every open PR |

## Keyboard

| Key | Action |
|-----|--------|
| `j`/`k` | Navigate up/down |
| `h`/`l` | Previous/next section |
| `g`/`G` | First/last item |
| `Enter` | Open selected item |
| `r` | Refresh now |
| `Esc` | Close panel |

Mouse: left-click toggles, right-click refreshes.

## PR status classification

| Status | Criteria |
|--------|----------|
| `ready` | Approved + CI passed + `mergeable == true` (not draft) |
| `approved_ci_passed` | Approved + CI passed but mergeability unknown |
| `approved` | Approved, CI not yet passed |
| `ci_passed` | CI passed, no approvals yet |
| `ci_running` | CI checks pending |
| `ci_failed` | CI failed or errored |
| `changes_requested` | Reviewer requested changes (latest review per reviewer) |
| `review_requested` | You are a requested reviewer |
| `draft` | Draft PR (never classified as ready) |
| `conflicted` | Merge conflicts (`mergeable == false`) |
| `open` | None of the above |

## Tests

Run the full test suite — no network, no Gitea, no Quickshell needed:

```bash
bash tests/run-all.sh
```

### Test suites

| Suite | Tests | What it covers |
|-------|-------|----------------|
| `test-jq-transform.sh` | 45 | PR classification, draft/conflict/mergeability guards, latest-review-per-reviewer, blocker detection, CI summaries, Actions fixture fields, section bucketing |
| `test-model.sh` | 32 | Parsing, filtering, muted-repo exclusion from counts + notifications, identity-based notification transitions (same-state no-repeat, new-PR-fires-even-if-count-same), statusIcon coverage |
| `test-collector-validation.sh` | 13 | Bash syntax, jq syntax, missing-credentials error path, empty-URL error path, ownership-safe lock reclaim, **full mocked collector execution** with canned HTTP responses asserting valid structured output |

### What is not tested here

| Category | Why | How to validate locally |
|----------|-----|------------------------|
| QML rendering | Requires Omarchy/Quickshell runtime | `qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml components/*.qml` |
| Manifest validity | Requires `omarchy plugin validate` | `omarchy plugin validate ~/.config/omarchy/plugins/gitea.workstatus` |
| Live Gitea API | Requires real credentials + server | Install, configure credentials, check `overview.json` populates |
| Desktop notifications | Requires Quickshell NotificationServer | Observe notifications on first CI failure |
| Theme token binding | Requires live Omarchy theme | Visual inspection in the running shell |

### QML API notes

The QML files use:
- `BarWidget` as the root type (Omarchy bar-widget entry point)
- `PopupCard` for the panel
- `setting("key")` to read manifest settings
- `FileView` with `watchChanges: true`, `onLoaded`, `onFileChanged`, `text()`
- `Process` to invoke the collector via `bash`
- `Quickshell.Colors.*` for theme colors
- `Quickshell.Sizes.*` for dimensions
- `Quickshell.Services.Notifications` for desktop notifications

These match the Quickshell/Omarchy runtime contract documented for Quattro.
The exact namespace paths (`Quickshell.Colors` vs `Quickshell.Theming`) may
need adjustment for your specific Omarchy build — run `qmllint` to verify.

## Architecture

```
gitea-workstatus/
├── manifest.json              Plugin manifest (bar-widget kind)
├── BarWidget.qml              Bar widget: icon + counts, file watcher, collector
├── Panel.qml                  Drop-down panel with reactive sections
├── Model.js                   State, filtering, identity-based notifications
├── components/
│   ├── PrRow.qml              PR row: status, reviews, CI, blockers, labels
│   ├── JobRow.qml             CI job row with status animation
│   ├── SummaryBadge.qml       Section tab badges (reactive)
│   ├── RepoFilter.qml         Repo filter chips
│   ├── EmptyState.qml         Per-section empty state
│   └── ErrorState.qml         Error + setup guidance
├── bin/
│   ├── gitea-collect           Bash collector (launched via bash, no exec bit needed)
│   └── gitea-collect.jq        JQ transform: latest-review, mergeability, draft guards
└── tests/
    ├── run-all.sh              Suite runner
    ├── test-jq-transform.sh    45 tests: classification, regressions
    ├── test-model.sh           32 tests: notifications, muting, filtering
    ├── test-collector-validation.sh  13 tests: syntax, errors, mocked execution
    └── mock-responses/         Gitea API fixtures (1.20+ format)
```

## License

MIT
