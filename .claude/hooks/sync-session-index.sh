#!/usr/bin/env bash
# Incrementally syncs .claude/session-index.tsv: adds any session transcripts
# present on disk but missing from the index. Cheaper than rebuild for the
# common case where only a handful of new sessions need to be picked up
# (e.g. when the SessionEnd hook didn't fire, or the agent is called mid-session).

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_claude_dir="$(dirname "$script_dir")"
project_root="$(dirname "$project_claude_dir")"
index_file="$project_claude_dir/session-index.tsv"
update_script="$script_dir/update-session-index.sh"

escaped="$(printf '%s' "$project_root" | sed 's|[/_.]|-|g')"
sessions_dir="$HOME/.claude/projects/$escaped"

if [[ ! -d "$sessions_dir" ]]; then
  echo "No sessions directory at $sessions_dir" >&2
  exit 1
fi

touch "$index_file"

# Snapshot currently indexed session ids (column 2).
indexed_ids_file=$(mktemp)
trap 'rm -f "$indexed_ids_file"' EXIT
awk -F '\t' '{print $2}' "$index_file" | sort -u > "$indexed_ids_file"

# Identify the currently-active session by newest mtime and exclude it.
# Rationale: during an active session its jsonl is the most-recently-written
# file by definition. Indexing it would cause session-explorer to return the
# current conversation as a "past" result. The SessionEnd hook (or the next
# sync invocation from a later session) will pick it up once it is no longer
# the newest file on disk.
shopt -s nullglob
current_session=""
for f in "$sessions_dir"/*.jsonl; do
  if [[ -z "$current_session" || "$f" -nt "$current_session" ]]; then
    current_session="$f"
  fi
done

added=0
for f in "$sessions_dir"/*.jsonl; do
  [[ "$f" == "$current_session" ]] && continue
  sid="$(basename "$f" .jsonl)"
  if ! grep -qxF "$sid" "$indexed_ids_file"; then
    "$update_script" "$f" || echo "warn: failed on $f" >&2
    added=$((added + 1))
  fi
done

excluded_name="$(basename "${current_session:-none}" .jsonl)"
echo "Added $added new session(s) to index (excluded active: $excluded_name)."
