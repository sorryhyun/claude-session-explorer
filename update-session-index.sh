#!/usr/bin/env bash
# Upserts one line into .claude/session-index.tsv for a given Claude Code session transcript.
#
# Two invocation modes:
#   1. SessionEnd hook: receives JSON on stdin with .transcript_path
#   2. Backfill:        receives the transcript path as $1
#
# Index columns (tab-separated, sorted newest-first):
#   <first-timestamp>  <session-id>  <git-branch>  <first-user-message-trimmed>

set -euo pipefail

# --- Resolve transcript path (arg wins over stdin) ---
transcript_path=""
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  transcript_path="$1"
elif [[ ! -t 0 ]]; then
  stdin_json=$(cat || true)
  if [[ -n "$stdin_json" ]]; then
    transcript_path=$(printf '%s' "$stdin_json" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  fi
fi

if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
  exit 0
fi

# --- Locate index file in the project's .claude dir ---
# This script lives at <project>/.claude/hooks/update-session-index.sh
script_dir="$(cd "$(dirname "$0")" && pwd)"
project_claude_dir="$(dirname "$script_dir")"
index_file="$project_claude_dir/session-index.tsv"

# --- Derive session id from filename ---
session_id="$(basename "$transcript_path" .jsonl)"

# --- Extract first user-authored text message ---
# User content may be a string or an array of blocks; handle both.
# Filter out slash-command wrappers, system reminders, and attachment blobs.
first_user=$(
  jq -r '
    select(.type=="user") |
    select(.message != null and .message.content != null) |
    .message.content
    | if type=="string"
      then .
      else (map(select(.type=="text") | .text) | join(" "))
      end
  ' "$transcript_path" 2>/dev/null \
    | awk 'NF' \
    | grep -avE '^[[:space:]]*<(command-name|command-message|command-args|local-command|attachment|system-reminder|user-prompt-submit-hook)' \
    | head -1 \
    | tr '\r\n\t' '   ' \
    | sed -E 's/  +/ /g; s/^ +//; s/ +$//' \
    | cut -c1-140 \
  || true
)
[[ -z "$first_user" ]] && first_user="(no user message)"

# --- First timestamp in the file ---
first_ts=$(
  jq -r 'select(.timestamp) | .timestamp' "$transcript_path" 2>/dev/null \
    | head -1 \
  || true
)
[[ -z "$first_ts" ]] && first_ts="0000-00-00T00:00:00Z"

# --- Git branch from the first event that records one ---
branch=$(
  jq -r 'select(.gitBranch != null and .gitBranch != "") | .gitBranch' "$transcript_path" 2>/dev/null \
    | head -1 \
  || true
)
[[ -z "$branch" ]] && branch="-"

# --- Upsert: drop any existing line for this session_id, append new one, sort desc ---
mkdir -p "$project_claude_dir"
touch "$index_file"

tmp=$(mktemp)
# Remove prior row for this session id (column 2). Tolerate grep's exit 1 on empty.
awk -F '\t' -v sid="$session_id" '$2 != sid' "$index_file" > "$tmp" || true
printf '%s\t%s\t%s\t%s\n' "$first_ts" "$session_id" "$branch" "$first_user" >> "$tmp"
sort -r -o "$index_file" "$tmp"
rm -f "$tmp"
