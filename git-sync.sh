#!/bin/bash
set -euo pipefail

git add -A

if git diff --cached --quiet; then
    echo "No changes to commit."
else
    git commit -m "work"
fi

git pull --rebase
git push
