#!/bin/bash
set -euo pipefail

# Default commit message if none is provided.
commit_msg="work"

# Parse optional -m "Commit message" argument.
if [ "$#" -ge 2 ] && [ "$1" = "-m" ]; then
    commit_msg="$2"
    shift 2
fi

# Stage all changes and commit if there is anything staged.
git add -A

if git diff --cached --quiet; then
    echo "No changes to commit."
else
    git commit -m "${commit_msg}"
fi

# Fetch remote state before deciding how to integrate.
git fetch

# Determine the current branch and its upstream tracking branch.
current_branch=$(git branch --show-current)
upstream="origin/${current_branch}"

# Verify the upstream branch exists on the remote.
if ! git rev-parse --verify "${upstream}" > /dev/null 2>&1; then
    echo "No upstream branch ${upstream} found; skipping rebase."
    git push -u origin "${current_branch}"
    exit 0
fi

# Check whether the current HEAD is already contained in the upstream branch.
# If it is, there are no local-only commits to rebase; a fast-forward pull is enough.
if git merge-base --is-ancestor HEAD "${upstream}"; then
    echo "HEAD is already present on ${upstream}; fast-forwarding local branch."
    git merge --ff-only "${upstream}"
else
    echo "Local commits are not yet on ${upstream}; rebasing."
    git rebase "${upstream}"
fi

# Push local commits to the remote.
git push
