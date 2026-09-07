#!/bin/sh
# Fetch the live issue taxonomy for the current GitHub repository. A section
# with no data prints "(none)" rather than being omitted, so the agent reading
# this can branch on absence.

set -eu

CACHE_DIR="${TMPDIR:-/tmp}/manage-issues-cache"
TTL_SECS=$((24 * 3600))
USE_CACHE=0

for arg in "$@"; do
  case "$arg" in
  --cached) USE_CACHE=1 ;;
  *)
    echo "ERROR: unknown flag: $arg" >&2
    exit 2
    ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found. Install from https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh not authenticated. Run: gh auth login" >&2
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
if [ -z "$REPO" ]; then
  echo "ERROR: not inside a GitHub repository" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/$(echo "$REPO" | tr '/' '_').txt"

if [ "$USE_CACHE" -eq 1 ] && [ -f "$CACHE_FILE" ]; then
  AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE")))
  if [ "$AGE" -lt "$TTL_SECS" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

OWNER="${REPO%%/*}"
TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' 0

{
  echo "CACHED_AT: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "REPO: $REPO"

  HAS_ISSUES=$(gh repo view --json hasIssuesEnabled -q '.hasIssuesEnabled' 2>/dev/null || echo "false")
  echo "ISSUES_ENABLED: $HAS_ISSUES"

  if [ "$HAS_ISSUES" != "true" ]; then
    echo ""
    echo "(Issues are disabled for this repository. Stop and inform the user.)"
  else
    echo ""
    echo "--- ISSUE_TYPES ---"
    if issue_types=$(gh api "/orgs/${OWNER}/issue-types" \
      --jq '.[] | "\(.name)\t\(.node_id)\t\(.description // "")"' 2>/dev/null); then
      if [ -z "$issue_types" ]; then
        echo "(none)"
      else
        echo "$issue_types" | sort | awk -F'\t' '{ printf "  %-14s  node_id=%-38s  %s\n", $1, $2, $3 }'
      fi
    else
      echo "(none; not configured for this owner)"
    fi
    echo ""

    if labels_raw=$(gh label list --limit 200 --json name,description \
      --jq '.[] | "\(.name)\t\(.description // "")"' 2>/dev/null); then
      :
    else
      labels_raw=""
    fi

    echo "--- LABEL_PREFIXES ---"
    if [ -z "$labels_raw" ]; then
      echo "(none)"
    else
      prefixes=$(echo "$labels_raw" | awk -F'\t' '{print $1}' | awk -F':' 'NF>1 {print $1}' | sort -u | tr '\n' ' ' | sed 's/ $//')
      if [ -z "$prefixes" ]; then
        echo "(none; repo uses flat labels)"
      else
        echo "  $prefixes"
      fi
    fi
    echo ""

    echo "--- LABELS ---"
    if [ -z "$labels_raw" ]; then
      echo "  (none)"
    else
      echo "$labels_raw" | sort | awk -F'\t' '{ printf "  %-32s  %s\n", $1, $2 }'
    fi
    echo ""

    echo "--- MILESTONES (open) ---"
    if miles=$(gh api "repos/${REPO}/milestones?state=open" --paginate \
      -q '.[] | "\(.title)\t[open=\(.open_issues), closed=\(.closed_issues)]"' 2>/dev/null); then
      if [ -z "$miles" ]; then
        echo "  (none open)"
      else
        echo "$miles" | sort | awk -F'\t' '{ printf "  %-40s  %s\n", $1, $2 }'
      fi
    else
      echo "  (none open)"
    fi
    echo ""

    echo "--- PROJECT_BOARDS ---"
    if projs=$(gh project list --owner "${OWNER}" --limit 10 --format json \
      --jq '.projects[]? | "  \(.title) (#\(.number))"' 2>/dev/null); then
      if [ -z "$projs" ]; then
        echo "  (none found)"
      else
        echo "$projs"
      fi
    else
      echo "  (none found; if you expected projects, run: gh auth refresh -s project,read:project)"
    fi
  fi
} >"$TMP_OUT"

cp "$TMP_OUT" "$CACHE_FILE"
cat "$CACHE_FILE"
