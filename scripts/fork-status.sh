#!/usr/bin/env bash
# ABOUTME: Show divergence between our fork and upstream twilio-labs/serverless-toolkit.
# ABOUTME: Categorizes commits as upstream-PR, fork-only, or merged. Flags PR opportunities.

set -euo pipefail

FORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FORK_ROOT"

# Ensure upstream remote exists
if ! git remote get-url upstream &>/dev/null; then
  echo "Adding upstream remote..."
  git remote add upstream https://github.com/twilio-labs/serverless-toolkit.git
fi

echo "Fetching upstream..."
git fetch upstream --quiet 2>/dev/null

DOGFOOD_BRANCH="fork/dogfood"
if ! git rev-parse --verify "$DOGFOOD_BRANCH" &>/dev/null; then
  echo "ERROR: $DOGFOOD_BRANCH branch not found"
  exit 1
fi

echo ""
echo "=== Fork Status: $DOGFOOD_BRANCH vs upstream/main ==="
echo ""

# Commits in our fork but not upstream
AHEAD=$(git log --oneline upstream/main.."$DOGFOOD_BRANCH" --no-merges 2>/dev/null)
AHEAD_COUNT=$(echo "$AHEAD" | grep -c . 2>/dev/null || echo 0)

# Commits upstream but not in our fork
BEHIND_COUNT=$(git rev-list --count "$DOGFOOD_BRANCH"..upstream/main 2>/dev/null || echo 0)

echo "Ahead of upstream: $AHEAD_COUNT commits"
echo "Behind upstream:   $BEHIND_COUNT commits"
echo ""

if [[ "$AHEAD_COUNT" -eq 0 ]]; then
  echo "Fork is in sync with upstream. Nothing to track."
  exit 0
fi

# Categorize each commit
echo "── Fork commits ──"
echo ""

# Check open PRs from our fork
PRS=""
if command -v gh &>/dev/null; then
  PRS=$(gh pr list --repo twilio-labs/serverless-toolkit --author wittyreference --state all --json number,title,state,headRefName 2>/dev/null || true)
fi

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  SHA="${line%% *}"
  MSG="${line#* }"

  # Check if this commit is on a branch with an open PR
  BRANCHES=$(git branch --contains "$SHA" --format='%(refname:short)' 2>/dev/null | grep -v "$DOGFOOD_BRANCH" | grep -v "^main$" || true)
  PR_INFO=""
  CATEGORY="fork-only"

  for branch in $BRANCHES; do
    if [[ -n "$PRS" ]]; then
      PR_MATCH=$(echo "$PRS" | python3 -c "
import sys, json
prs = json.load(sys.stdin)
for pr in prs:
    if pr.get('headRefName','') == '$branch':
        print(f\"#{pr['number']} ({pr['state'].lower()})\")
        break
" 2>/dev/null || true)
      if [[ -n "$PR_MATCH" ]]; then
        PR_INFO=" → PR $PR_MATCH"
        CATEGORY="upstream-pr"
      fi
    fi
  done

  case "$CATEGORY" in
    upstream-pr)  printf "  📤 %s %s%s\n" "$SHA" "$MSG" "$PR_INFO" ;;
    fork-only)    printf "  🔧 %s %s\n" "$SHA" "$MSG" ;;
  esac
done <<< "$AHEAD"

echo ""

# Check for upstream changes we should rebase onto
if [[ "$BEHIND_COUNT" -gt 0 ]]; then
  echo "── Upstream changes to incorporate ──"
  echo ""
  git log --oneline "$DOGFOOD_BRANCH"..upstream/main | head -10
  if [[ "$BEHIND_COUNT" -gt 10 ]]; then
    echo "  ... and $((BEHIND_COUNT - 10)) more"
  fi
  echo ""
  echo "To update: git checkout $DOGFOOD_BRANCH && git rebase upstream/main"
fi

# Summary
echo ""
echo "── Summary ──"
UPSTREAM_PR_COUNT=0
FORK_ONLY_COUNT=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  SHA="${line%% *}"
  BRANCHES=$(git branch --contains "$SHA" --format='%(refname:short)' 2>/dev/null | grep "^feat/" || true)
  if [[ -n "$BRANCHES" ]]; then
    ((UPSTREAM_PR_COUNT++)) || true
  else
    ((FORK_ONLY_COUNT++)) || true
  fi
done <<< "$AHEAD"

echo "  Upstream PRs (pending/merged): $UPSTREAM_PR_COUNT"
echo "  Fork-only patches:             $FORK_ONLY_COUNT"
echo "  Behind upstream:               $BEHIND_COUNT"
echo ""
echo "When upstream merges a PR, rebase fork/dogfood to drop the merged commit."
