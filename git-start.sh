#!/bin/bash
set -euo pipefail

# Safer session-start sync.
# Fetches remote state, shows what changed, and integrates it carefully.

current_branch=$(git branch --show-current)
upstream="origin/${current_branch}"

echo "Fetching remote state..."
git fetch

# Verify the upstream branch exists.
if ! git rev-parse --verify "${upstream}" > /dev/null 2>&1; then
    echo "No upstream branch ${upstream} found."
    echo "You are on '${current_branch}' with no remote tracking branch."
    exit 0
fi

# Show commits on the remote that are not yet in your local branch.
remote_only=$(git log HEAD.."${upstream}" --oneline)
if [ -n "${remote_only}" ]; then
    echo ""
    echo "Remote commits not yet in your local branch:"
    echo "${remote_only}"
else
    echo "Your local branch is up to date with ${upstream}."
fi

# Show local commits that are not yet on the remote.
local_only=$(git log "${upstream}"..HEAD --oneline)
if [ -n "${local_only}" ]; then
    echo ""
    echo "Local commits not yet pushed to ${upstream}:"
    echo "${local_only}"
fi

# Decide how to integrate.
if git merge-base --is-ancestor HEAD "${upstream}"; then
    echo ""
    echo "HEAD is already present on ${upstream}; fast-forwarding local branch."
    git merge --ff-only "${upstream}"
elif [ -n "${local_only}" ]; then
    echo ""
    echo "Local commits are not yet on ${upstream}."
    read -r -p "Rebase local commits onto ${upstream}? [y/N] " answer
    if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        git rebase "${upstream}"
    else
        echo "Skipping rebase. Run 'git rebase ${upstream}' or 'git merge ${upstream}' manually when ready."
        exit 0
    fi
else
    echo ""
    echo "Local and remote histories have diverged."
    read -r -p "Rebase onto ${upstream}? [y/N] " answer
    if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
        git rebase "${upstream}"
    else
        echo "Skipping rebase. Resolve manually when ready."
        exit 0
    fi
fi
