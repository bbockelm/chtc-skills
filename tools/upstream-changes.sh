#!/usr/bin/env bash
#
# Show what changed in the upstream CHTC repositories since the last time the
# skills in this repo were reviewed against them.
#
# The "last review" is whatever commit each submodule is pinned to in HEAD of
# this repository. Fetching moves the comparison target to the upstream tip;
# the diff between the two is the review queue.
#
#   tools/upstream-changes.sh            # commits + changed files per repo
#   tools/upstream-changes.sh --patch    # full diffs
#   tools/upstream-changes.sh --pin      # stage the new tips (AFTER updating skills)
#
# Written for bash 3.2 so it runs on stock macOS.

set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-summary}"

# Each entry is "<submodule path>:<space-separated paths that feed the skills>".
# Changes outside those paths are ignored -- the website repo carries events,
# news and staff pages that have nothing to do with running jobs.
SUBMODULES="
upstream/chtc-website-source:_uw-research-computing
upstream/templates-GPUs:.
upstream/recipes:software workflows-htc
"

if [ "$MODE" = "--pin" ]; then
    echo "$SUBMODULES" | while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        git add "${entry%%:*}"
    done
    echo "Staged new submodule pointers. Commit them together with the skill updates."
    exit 0
fi

echo "$SUBMODULES" | while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    sub="${entry%%:*}"
    scope="${entry#*:}"

    pinned=$(git ls-tree HEAD "$sub" | awk '{print $3}')
    ( cd "$sub" && git fetch --quiet origin )
    tip=$(cd "$sub" && git rev-parse FETCH_HEAD)

    echo "==================================================================="
    echo "$sub"
    echo "  reviewed at:  ${pinned:0:12}"
    echo "  upstream tip: ${tip:0:12}"
    echo "==================================================================="

    if [ "$pinned" = "$tip" ]; then
        echo "  (no change)"
        echo
        continue
    fi

    # Move the checkout to the tip so the reviewing agent reads current text.
    ( cd "$sub" && git checkout --quiet "$tip" )

    if [ "$MODE" = "--patch" ]; then
        # shellcheck disable=SC2086
        ( cd "$sub" && git diff "$pinned" "$tip" -- $scope )
    else
        # shellcheck disable=SC2086
        ( cd "$sub" && git log --oneline "$pinned..$tip" -- $scope )
        echo
        # shellcheck disable=SC2086
        ( cd "$sub" && git diff --stat "$pinned" "$tip" -- $scope )
    fi
    echo
done

echo "For each changed file, find the skills that claim it:"
echo "    grep -l '<path fragment>' skills/*.md"
echo "Then update those skills, bump their 'upstream_reviewed:' date, and run:"
echo "    tools/upstream-changes.sh --pin"
