#!/usr/bin/env bash
# ABOUTME: Link this fork's packages into a consuming project via npm link.
# ABOUTME: Re-run after npm install in either repo to restore the symlinks.

set -euo pipefail

FORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-$HOME/workspaces/twilio-feature-factory}"

if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: Target project not found at $TARGET"
  echo "Usage: $0 [/path/to/project]"
  exit 1
fi

echo "=== Linking serverless-toolkit fork ==="
echo "Fork:    $FORK_ROOT"
echo "Target:  $TARGET"
echo ""

# Step 1: Register fork packages globally
for pkg in twilio-run serverless-api; do
  echo "  npm link packages/$pkg"
  (cd "$FORK_ROOT/packages/$pkg" && npm link --silent) || {
    echo "  WARN: npm link failed for $pkg — try building first: npm run build"
    exit 1
  }
done

# Step 2: Link into target project
echo ""
echo "  Linking into target project..."
(cd "$TARGET" && npm link twilio-run @twilio-labs/serverless-api --silent)

# Step 3: Verify
echo ""
echo "=== Verification ==="
for pkg in twilio-run @twilio-labs/serverless-api; do
  LINK=$(readlink "$TARGET/node_modules/$pkg" 2>/dev/null || true)
  if [[ -n "$LINK" && "$LINK" == *"serverless-toolkit"* ]]; then
    echo "  ✓ $pkg → $LINK"
  else
    echo "  ✗ $pkg is NOT linked (got: ${LINK:-<not a symlink>})"
  fi
done

echo ""
echo "Fork is linked. Run tests: cd $TARGET && npm test"
