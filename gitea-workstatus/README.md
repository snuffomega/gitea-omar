# gitea.workstatus — Gitea Work Status for Omarchy 4

A native Omarchy shell bar widget that monitors your self-hosted Gitea instance:
open PRs, review requests, CI status, and running jobs — all in one glance.

**Requires Gitea >= 1.19.** Actions/CI monitoring requires Gitea >= 1.20.

## Features

- **Compact bar summary**: failed CI, pending reviews, running jobs — color-coded,
  pulsing when active, quiet when healthy
- **Prioritized panel**: Attention -> Running -> Completed -> My PRs -> Review Queue
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
- **Cold-start suppression**: the first data load after shell start seeds
  notification state silently — no flood of alerts for existing failures
- **Stale data carry-forward**: if connectivity drops or the API returns empty
  results, last-good data is preserved (marked stale) for up to `maxStaleHours`.
  Triggers when EITHER PRs or runs are empty (not requiring both).
- **Atomic writes**: output JSON is written atomically via temp+rename
- **flock-based locking**: mutual exclusion via `flock(1)` — no TOCTOU race,
  no stale PID checks
- **Error preservation**: API failures write to a separate error file, never
  overwrite last-good overview data

## Runtime dependencies

| Dependency | Purpose | Provided by Omarchy |
|------------|---------|---------------------|
| `bash` | Collector script | Yes |
| `curl` | Gitea API calls | Yes |
| `jq` (>= 1.6) | JSON transforms | Yes |
| `flock` (util-linux) | Collector mutual exclusion | Yes |
| `coreutils` (`mktemp`, `date`, `base64`) | Utilities | Yes |
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
| `giteaUrl` | string | --- | Gitea instance URL |
| `maxStaleHours` | integer | 6 | Hours before stale data is hidden |
| `notifyOnFailure` | boolean | true | Notify on CI failure |
| `notifyOnReviewRequest` | boolean | true | Notify on review request |
| `mutedRepos` | string | --- | Comma-separated `owner/repo` to exclude |

## Bar Widget

Color-coded compact indicators:

| Indicator | Meaning |
|-----------|---------|
| Red X N | N PRs with failed CI |
| Blue dot N | N PRs awaiting your review |
| Amber circle N (pulsing) | N jobs running |
| Green check N | N PRs approved with CI passed |

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
| `approved_ci_passed` | Approved + CI passed + `mergeable == true` (or unknown) |
| `approved` | Approved, CI not yet passed |
| `ci_passed` | CI passed, no approvals yet |
| `ci_running` | CI checks pending |
| `ci_failed` | CI failed or errored |
| `changes_requested` | Reviewer requested changes (latest review per reviewer) |
| `review_requested` | You are a requested reviewer |
| `draft` | Draft PR (never classified as ready) |
| `conflicted` | Merge conflicts (`mergeable == false`) |
| `open` | None of the above |

**Note:** `approved_ci_passed` means "approved with CI green" but does NOT
guarantee the PR is actually mergeable. Gitea does not expose branch-protection
rules via its API, so the plugin cannot verify required review counts,
required status checks, or push permissions. Treat `approved_ci_passed` as
"looks good from the API" — the merge button in the Gitea UI is the authority.

## Tests

Run the full test suite — no network, no Gitea, no Quickshell needed:

```bash
bash tests/run-all.sh
```

### Test suites

| Suite | What it covers |
|-------|----------------|
| `test-jq-transform.sh` | PR classification, draft/conflict/mergeability guards, latest-review-per-reviewer, blocker detection, CI summaries, Actions fixture fields, section bucketing |
| `test-model.sh` | Parsing, filtering, muted-repo exclusion from counts + notifications, cold-start notification suppression, identity-based notification transitions (same-state no-repeat, new-PR-fires-even-if-count-same), statusIcon coverage |
| `test-collector-validation.sh` | Bash syntax, jq syntax, missing-credentials error, empty-URL error, flock locking, full mocked collector, HTTP 500 on repos, auth failure preserving data, malformed JSON, PR failures with Actions, Actions-only repos, stale carry-forward, concurrent collector contention |

### What is not tested here

| Category | Why | How to validate locally |
|----------|-----|------------------------|
| QML rendering | Requires Omarchy/Quickshell runtime | See QML verification below |
| Manifest validity | Requires `omarchy plugin validate` | `omarchy plugin validate ~/.config/omarchy/plugins/gitea.workstatus` |
| Live Gitea API | Requires real credentials + server | Install, configure credentials, check `overview.json` populates |
| Desktop notifications | Requires `notify-send` + notification daemon | Observe notifications on first CI failure after shell restart |
| Theme token binding | Requires live Omarchy theme | Visual inspection in the running shell |

### QML API contract

The QML files use verified upstream Omarchy/Quickshell APIs:

| Import | Types/Properties used |
|--------|----------------------|
| `import qs.Ui as Ui` | `Ui.BarWidget {}` root, `setting(name, fallback)` (2 args), `bar`, `moduleName`, `broadcast()` |
| `import qs.Commons` | `Color.text.{primary,secondary,muted}`, `Color.status.{error,warning,success}`, `Color.accent.{primary,secondary}`, `Color.popups.{background,border}`, `Style.space(N)`, `Style.bar.sizeHorizontal`, `Style.cornerRadius`, `Style.font.{family,monospace}` |
| `Ui.PopupCard {}` | `anchorItem` (required Item), `bar` (required QtObject), `contentWidth`, `contentHeight`, `close()` |
| `Quickshell.Io` | `FileView { path, watchChanges, loaded, text(), onLoadedChanged, onFileChanged }`, `Process { command, started(), exited(), stdout() }` |

**Not used** (common mistakes in earlier versions):
- `FileView.reload()` — does not exist; set `blockLoading` then unset, or use `watchChanges`
- `onLoaded:` signal — `loaded` is a property; use `onLoadedChanged: if (loaded) ...`
- `NotificationServer` — that is the aggregator; sending uses `notify-send` via `Process`
- `Quickshell.Colors.*`, `Quickshell.Sizes.*` — do not exist; use `Color.*`, `Style.*` from `qs.Commons`

### QML verification commands

```bash
# Requires Omarchy shell modules on the import path
OMARCHY_SHELL=~/.config/omarchy/shell
qmllint -I "$OMARCHY_SHELL" BarWidget.qml Panel.qml components/*.qml

# Dry-run: check QML parses without the full runtime
qmlscene --quit BarWidget.qml 2>&1 | head -20
```

## Architecture

```
gitea-workstatus/
+-- manifest.json              Plugin manifest (bar-widget kind)
+-- BarWidget.qml              Bar widget: icon + counts, file watcher, collector
+-- Panel.qml                  Drop-down panel with reactive sections
+-- Model.js                   State, filtering, identity-based notifications
+-- components/
|   +-- PrRow.qml              PR row: status, reviews, CI, blockers, labels
|   +-- JobRow.qml             CI job row with status animation
|   +-- SummaryBadge.qml       Section tab badges (reactive)
|   +-- RepoFilter.qml         Repo filter chips
|   +-- EmptyState.qml         Per-section empty state
|   +-- ErrorState.qml         Error + setup guidance
+-- bin/
|   +-- gitea-collect           Bash collector (flock, atomic writes, error preservation)
|   +-- gitea-collect.jq        JQ transform: latest-review, mergeability, draft guards
+-- tests/
    +-- run-all.sh              Suite runner
    +-- test-jq-transform.sh    Classification, regressions
    +-- test-model.sh           Notifications, muting, filtering
    +-- test-collector-validation.sh  Syntax, errors, mocked execution, failure scenarios
    +-- mock-responses/         Gitea API fixtures (1.20+ format)
```

## Limitations

1. **No branch protection awareness.** The Gitea API does not expose branch
   protection rules to non-admin tokens. The plugin cannot verify required
   review counts or required status checks. `approved_ci_passed` is a best
   guess, not a guarantee.

2. **Actions support is best-effort.** Gitea < 1.20 does not have the Actions
   API. The plugin silently skips Actions data on older servers. Repos with
   Actions disabled return 404 — this is treated as "no runs", not an error.

3. **No real-time updates.** The plugin polls on a timer (default 3 minutes).
   Webhook-driven push is not supported.

4. **Single-user, single-instance.** Credentials are per-user. There is no
   multi-account or multi-server support.

5. **QML not verified at build time.** The QML files target Omarchy 4 /
   Quickshell and cannot be type-checked without the runtime. The API contract
   was verified against upstream source (see table above) but runtime binding
   errors are possible. Run `qmllint` on an Omarchy system to confirm.

## License

MIT
