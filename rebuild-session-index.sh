#!/usr/bin/env bash
# Rebuilds .claude/session-index.tsv from scratch by walking every transcript
# JSONL in this project's Claude Code session directory.
#
# Safe to re-run: upsert semantics in update-session-index.sh keep the index
# deduped by session id. This script wipes the index first for a clean rebuild.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_claude_dir="$(dirname "$script_dir")"
project_root="$(dirname "$project_claude_dir")"
index_file="$project_claude_dir/session-index.tsv"
update_script="$script_dir/update-session-index.sh"

# Derive the Claude Code sessions directory from the project root.
# Claude Code escapes the absolute path by replacing '/', '_', and '.' with '-'.
escaped="$(printf '%s' "$project_root" | sed 's|[/_.]|-|g')"
sessions_dir="$HOME/.claude/projects/$escaped"

if [[ ! -d "$sessions_dir" ]]; then
  echo "No sessions directory at $sessions_dir" >&2
  exit 1
fi

: > "$index_file"

count=0
shopt -s nullglob
for f in "$sessions_dir"/*.jsonl; do
  "$update_script" "$f" || echo "warn: failed on $f" >&2
  count=$((count + 1))
done

echo "Rebuilt $index_file with $count sessions."
