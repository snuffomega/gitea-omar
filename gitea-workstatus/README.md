# gitea.workstatus — Gitea Work Status for Omarchy

A native Omarchy shell bar widget that monitors your self-hosted Gitea instance:
open PRs, review requests, CI status, and running jobs — all in one glance.

## Features

- **Compact bar summary**: failed CI, pending reviews, running jobs — color-coded,
  pulsing when active, quiet when healthy
- **Prioritized panel**: Needs Attention → Running → Recently Completed → My PRs → Review Queue
- **Blocker explanations**: a passing CI alone does not mean ready to merge —
  blockers surface review state, merge conflicts, and missing approvals
- **One-click navigation**: open any PR, failed job, or repository directly in
  your browser
- **Repo filtering**: select a repo to focus on, or mute repos you do not care about
- **Keyboard-driven**: j/k navigate, h/l switch sections, Enter opens, r refreshes, Esc closes
- **Notifications**: alerts on new CI failures and review requests, with 10-minute
  deduplication to avoid noise
- **Stale data handling**: if a connection drops, the last good data is carried
  forward (marked stale) for up to 6 hours
- **Parallel collection**: each repo is collected concurrently — the run costs the
  slowest repo, not the sum

## Requirements

- [Omarchy 4 (Quattro)](https://omarchy.org) with Quickshell
- `curl`, `jq` (both are standard on Omarchy)
- A Gitea instance with API access (token with `read:issue`, `read:repository`,
  `read:user` scopes)

## Install

### 1. Clone into your plugins directory

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
read-only scopes.

### 3. Enable the plugin

```bash
omarchy plugin enable gitea.workstatus
```

Or force discovery:

```bash
omarchy-shell shell rescanPlugins
```

The widget appears in the right section of your bar by default.

## Configuration

Settings are exposed through the Omarchy plugin settings UI. You can also
set them in the manifest defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `refreshIntervalSec` | 180 | How often to poll Gitea (seconds) |
| `giteaUrl` | — | Your Gitea instance URL |
| `maxStaleHours` | 6 | Hours before stale data is hidden |
| `notifyOnFailure` | true | Desktop notification on CI failure |
| `notifyOnReviewRequest` | true | Notification on new review request |
| `mutedRepos` | — | Comma-separated `owner/repo` to hide |

## Bar Widget

The bar shows compact status using color-coded indicators:

- **Red** `✘ N` — N PRs with failed CI
- **Blue** `● N` — N PRs awaiting your review
- **Amber** `◦ N` — N jobs running (pulses)
- **Green** `✔ N` — N PRs ready to merge

When everything is healthy, the icon is subdued. An `!` appears on error.

## Panel Sections

| Section | Shows |
|---------|-------|
| Attention | PRs with failed CI, requested changes, or your review needed |
| Running | Active CI/CD jobs |
| Completed | Recent job results (success and failure) |
| My PRs | PRs you authored |
| Review | PRs where you are a requested reviewer |
| All | Every open PR |

Each PR row shows: status dot, title, repo, branch, author, review counts,
CI check counts, blocker reason, and relative timestamp.

## Keyboard

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate up/down |
| `h` / `l` | Previous/next section |
| `g` / `G` | First/last item |
| `Enter` | Open selected item |
| `r` | Refresh now |
| `Esc` | Close panel |

Mouse: left-click toggles panel, right-click refreshes.

## Keybinding

Bind the panel to a key via `~/.config/hypr/bindings.lua`:

```lua
bind("$mod", "G", "exec", "omarchy-shell gitea.workstatus toggle")
```

Available IPC commands: `toggle`, `open`, `close`, `refresh`.

## How It Works

`bin/gitea-collect` runs on a timer and writes JSON to
`~/.local/state/omarchy/gitea-workstatus/overview.json`. The QML panel
watches this file.

The collector:
1. Authenticates and fetches your repos
2. For each repo with PRs enabled, fetches open PRs concurrently
3. For each PR, fetches reviews and commit status
4. Fetches action runs for CI/CD monitoring
5. Pipes everything through `bin/gitea-collect.jq` to classify and prioritize

API calls are parallelized per-repo (8 concurrent). A lock file prevents
overlapping runs. Connection failures carry forward the last good data.

## Tests

Run the full test suite — no network or Gitea credentials needed:

```bash
bash tests/run-all.sh
```

| Suite | What it tests |
|-------|---------------|
| `test-jq-transform.sh` | PR classification, blocker detection, review/CI summaries, section bucketing |
| `test-model.sh` | JS model: parsing, filtering, muting, notifications, time formatting |
| `test-collector-validation.sh` | Script syntax, error handling for missing credentials |

## What Is Not Yet Tested

- **QML rendering**: the bar widget and panel require the Omarchy/Quickshell
  runtime which is not available in this build environment. To validate locally:
  ```bash
  qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml components/*.qml
  omarchy plugin validate ~/.config/omarchy/plugins/gitea.workstatus
  ```
- **Live API integration**: the collector is tested for syntax and error paths
  but not against a real Gitea instance. Point it at your Gitea and confirm
  `~/.local/state/omarchy/gitea-workstatus/overview.json` populates correctly.
- **Notification delivery**: depends on the Omarchy `Notifications` API at
  runtime.

## Architecture

```
gitea-workstatus/
├── manifest.json           Plugin manifest (bar-widget kind)
├── BarWidget.qml           Compact bar: icon + counts
├── Panel.qml               Drop-down panel with sections
├── Model.js                State management, filtering, notifications
├── components/
│   ├── PrRow.qml           PR row with status, reviews, CI, blockers
│   ├── JobRow.qml           CI job row
│   ├── SummaryBadge.qml    Section tab badges
│   ├── RepoFilter.qml     Repo filter chips
│   ├── EmptyState.qml      Empty state per section
│   └── ErrorState.qml      Error + setup guidance
├── bin/
│   ├── gitea-collect        Bash data collector
│   └── gitea-collect.jq     JQ transform pipeline
└── tests/
    ├── run-all.sh           Test runner
    ├── test-jq-transform.sh
    ├── test-model.sh
    ├── test-collector-validation.sh
    └── mock-responses/      API response fixtures
```

## License

MIT
