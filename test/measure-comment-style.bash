#!/usr/bin/env bash
# Prices a comment-style rule change against code it has to stay silent on: runs
# the hook at a git revision and in the working tree over each corpus, and names
# every report the working tree adds.

set -euo pipefail
export LC_ALL=C

usage() {
  echo "usage: $0 [-r REF] [-x PATH_GLOB]... DIR:NAME_GLOB..." >&2
  exit 64
}

ref=main
excludes=()
while getopts r:x: opt; do
  case $opt in
  r) ref=$OPTARG ;;
  x) excludes+=(-not -path "$OPTARG") ;;
  *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || usage

root=$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

before_hook=$work/before.sh
after_hook=$root/.claude/hooks/check-comment-style.sh
git -C "$root" show "$ref:.claude/hooks/check-comment-style.sh" >"$before_hook"
chmod +x "$before_hook"

reports() {
  jq -n --arg path "$2" '{tool_input: {file_path: $path}}' |
    "$1" 2>&1 >/dev/null | grep '^  line ' || true
}

count() {
  if [ -z "$1" ]; then echo 0; else printf '%s\n' "$1" | wc -l; fi
}

# A hook that blocks nothing, as it does on a host without jq, reports every
# corpus clean, so both revisions must flag a known violation first.
probe=$work/probe.go
printf 'package p\n\n// Step 2: seed it\nvar x = 1\n' >"$probe"
for hook in "$before_hook" "$after_hook"; do
  if [ -z "$(reports "$hook" "$probe")" ]; then
    echo "$hook reports nothing on a known violation" >&2
    exit 1
  fi
done

status=0
printf '%-50s %7s %7s %7s\n' corpus files "$ref" worktree
for corpus in "$@"; do
  dir=${corpus%:*}
  name=${corpus##*:}
  files=0 before_total=0 after_total=0 added=""
  while IFS= read -r -d '' file; do
    before=$(reports "$before_hook" "$file")
    after=$(reports "$after_hook" "$file")
    files=$((files + 1))
    before_total=$((before_total + $(count "$before")))
    after_total=$((after_total + $(count "$after")))
    new=$(comm -13 <(printf '%s\n' "$before" | sort) <(printf '%s\n' "$after" | sort))
    [ -z "$new" ] || added+=$(printf '%s\n' "$new" | awk -v f="$file" '{ sub(/^ +/, ""); print "  + " f ": " $0 }')$'\n'
  done < <(find "$dir" -type f -name "$name" ${excludes[@]+"${excludes[@]}"} -print0)
  printf '%-50s %7d %7d %7d\n' "$dir" "$files" "$before_total" "$after_total"
  printf '%s' "$added"
  if [ "$files" -eq 0 ]; then
    echo "  no file under $dir matches $name; a zero here is not a clean corpus" >&2
    status=1
  fi
done
exit "$status"
