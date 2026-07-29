# GitPush — Using `git-sync.sh`

`git-sync.sh` is a convenience script that stages, commits, pulls, and pushes your current branch in one step. It is located in the repository root.

## Basic usage

```bash
./git-sync.sh
```

Stages all changes, commits them with the message `"work"`, safely integrates remote changes, and pushes to `origin`.

## Custom commit message

```bash
./git-sync.sh -m "Your commit message"
```

If you provide `-m "..."`, the script uses that message instead of `"work"`.

## What the script does

1. `git add -A` — stages all changes in the working tree.
2. `git commit -m "..."` — commits the staged changes if any exist.
3. `git fetch` — downloads the latest remote state without modifying your local branch.
4. Checks whether an upstream tracking branch exists (`origin/<current-branch>`).
5. Checks whether your current `HEAD` is already present on the upstream branch.
   - If yes, it performs a fast-forward merge (`git merge --ff-only`).
   - If no, it rebases your local-only commits (`git rebase`).
6. `git push` — pushes the result to the remote.

## Why rebase is conditional

Rebasing rewrites commit hashes. If your commits are already on the remote, rebasing would rewrite public history and require a force push. The script avoids this by fast-forwarding when your `HEAD` is already an ancestor of the upstream branch.

## When to use this script

Use it when:

- You are the only person on the branch.
- You want a quick sync with a clean, linear history.
- You do not need a carefully written commit message (use `-m` for better messages).

## When not to use this script

Avoid it when:

- Multiple people share the branch and your commits are already pushed.
- You want to review exactly what will be committed or pushed.
- You need to keep some working-tree changes unstaged.
- You want to preserve the `Co-Authored-By: Claude <noreply@anthropic.com>` signature for AI-assisted commits. The script does not add this automatically.

## Important notes

- The script stages **all** changes (`git add -A`), including untracked files and deletions.
- The default commit message `"work"` is not descriptive. Prefer `-m` with a meaningful message.
- If the upstream branch does not exist yet, the script pushes with `-u` to set the upstream tracking branch.
