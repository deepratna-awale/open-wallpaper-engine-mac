#!/bin/bash
# Steam QR sign-in research, run by hand in Terminal: bash run-all.sh
# Writes results to $S/results.log. Never prints tokens.
S=/Volumes/980Pro/.claude/steam-login-research
P=$S/probe
R=/Volumes/980Pro/Workspace/steam-login-research
LOG=$R/results.log
: > "$LOG"
say() { echo "== $*" | tee -a "$LOG"; }
field() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$1" "$2"; }

say "1. SteamProbe with the earlier sign-in's refresh token"
cp "$S/tokens-platform1.json" "$S/tokens-old.json"
"$P/SteamProbe" "$S/tokens-old.json" 2>&1 | tee -a "$LOG"

say "2. New QR sign-in (scan the QR code that opens in Preview)"
python3 "$R/probe.py" "$S" 1 2>&1 | tee -a "$LOG"
osascript -e 'tell application "Preview" to close (every window whose name contains "qr.png")' >/dev/null 2>&1
rm -f "$S/qr.png"

say "3. SteamProbe with the new refresh token"
"$P/SteamProbe" "$S/tokens-platform1.json" 2>&1 | tee -a "$LOG"

ACCOUNT=$(field "$S/tokens-platform1.json" account)
export OWE_STEAM_REFRESH_TOKEN=$(field "$S/tokens-platform1.json" refresh)
ID=$(python3 - "$S/tokens-platform1.json" <<'PY'
import json, sys, urllib.parse, urllib.request
t = json.load(open(sys.argv[1]))
q = urllib.parse.urlencode({"appid": 431960, "numperpage": 1, "query_type": 1, "requiredtags[0]": "Everyone", "requiredtags[1]": "Scene", "match_all_tags": 1, "access_token": t["access"]})
with urllib.request.urlopen(f"https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/?{q}", timeout=30) as r:
    f = json.load(r)["response"]["publishedfiledetails"][0]
print(f["publishedfileid"])
PY
)
say "4. DepotDownloader Workshop download of item $ID (tags Everyone + Scene)"
START=$(date +%s)
"$P/DepotDownloader" -app 431960 -pubfile "$ID" -username "$ACCOUNT" -dir "$S/dl" 2>&1 | tail -30 | tee -a "$LOG"
echo "took $(( $(date +%s) - START ))s" | tee -a "$LOG"
find "$S/dl" -maxdepth 2 -exec ls -ld {} \; 2>&1 | awk '{print $5, $9}' | tee -a "$LOG"
[ -f "$S/dl/project.json" ] && echo "project.json present" | tee -a "$LOG"

say "5. DepotDownloader manifest only for the WE app (windows), nothing big downloaded"
"$P/DepotDownloader" -app 431960 -os windows -username "$ACCOUNT" -manifest-only -dir "$S/manifest" 2>&1 | tail -30 | tee -a "$LOG"
find "$S/manifest" -name "*.txt" | while read -r m; do
  echo "-- $m: $(wc -l < "$m") lines; assets/ entries: $(grep -c 'assets/' "$m")" | tee -a "$LOG"
  head -20 "$m" | tee -a "$LOG"
done
unset OWE_STEAM_REFRESH_TOKEN

say "6. Cleanup"
rm -rf "$S/dl" "$S/manifest"
find "$HOME/.local/share/IsolatedStorage" "$HOME/Library/Application Support/IsolatedStorage" -name account.config -mmin -60 -print -delete 2>/dev/null | tee -a "$LOG"
say "done; results in $LOG"
