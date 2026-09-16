#!/usr/bin/env bash
set -e
cd /tmp/cc-agent/70980686/project/gitea-workstatus
T=$(mktemp -d)
export XDG_STATE_HOME="$T/state"
export XDG_CONFIG_HOME="$T/config"
mkdir -p "$XDG_STATE_HOME/omarchy/gitea-workstatus" "$XDG_CONFIG_HOME/gitea-workstatus"
printf 'GITEA_URL="x"\nGITEA_TOKEN="t"\n' > "$XDG_CONFIG_HOME/gitea-workstatus/credentials"
mock_state="$XDG_STATE_HOME/omarchy/gitea-workstatus/overview.json"
orig=$(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ)
cat > "$mock_state" << EOF
{"meta":{"collected_at":"$orig","stale":false},"summary":{"open_prs":1},"sections":{"all_prs":[{"id":1,"repo":"t/r"}],"running":[],"recently_completed":[]},"repos":["t/r"]}
EOF
cat > "$T/curl" <<'CURL'
#!/usr/bin/env bash
url=""; w=false
for a in "$@"; do case "$a" in https://*) url="$a";; *http_code*) w=true;; esac; done
p=$(echo "$url" | grep -oP '/api/v1\K[^?]*' || echo "")
case "$p" in
  /user) echo '{"login":"u"}'; $w && printf '\n200' ;;
  /user/repos) echo '[{"owner":{"login":"t"},"name":"r"}]'; $w && printf '\n200' ;;
  /repos/*/pulls) echo '{}'; $w && printf '\n500' ;;
  /repos/*/actions/runs) echo '{"workflow_runs":[]}'; $w && printf '\n200' ;;
  *) echo '[]'; $w && printf '\n200' ;;
esac
exit 0
CURL
chmod +x "$T/curl"
PATH="$T:$PATH" bash bin/gitea-collect
echo "sectionallprs:"
jq -c '.sections.all_prs' "$mock_state"
echo "jq select t/r:"
jq '[.sections.all_prs[]? | select(.repo=="t/r")] | length' "$mock_state"
rm -rf "$T"