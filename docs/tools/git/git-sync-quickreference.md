# Sync a local Git repository with remote / upstream

Use this routine in order: **fetch first**, then **integrate on your current branch**, then **optionally refresh every local branch** that tracks a remote.

---

## 1. Sync with remote (always first)

Fetches all remotes, updates remote-tracking refs, and removes stale remote-tracking branches locally.

```bash
git fetch --all --prune
```

| Flag | Purpose |
|------|--------|
| `fetch` | Downloads new commits and updates refs like `origin/main`. Does **not** modify your current branch’s files by itself. |
| `--all` | Every configured remote (e.g. `origin`, `upstream`). |
| `--prune` | Drops remote-tracking branches that were deleted on the server. |

If you prefer to be explicit (e.g. fork with `origin` + `upstream`):

```bash
git fetch origin --prune
git fetch upstream --prune
```

(`git fetch --all --prune` already covers both once `upstream` is configured.)

---

## 2. Update the primary local branch

Replace `main` and `origin/main` with your default branch and its remote if different.

### Option A — merge (fast-forward only)

Safe default: only moves your branch pointer when history is strictly behind the remote.

```bash
git checkout main
git merge --ff-only origin/main
```

- **`--ff-only`**: Fails if you have local commits not on the remote; then choose rebase, a normal merge, or reset (see notes).

### Option B — rebase (linear history)

```bash
git checkout main
git rebase origin/main
```

- Replays your local commits on top of `origin/main`. Resolve conflicts if Git stops.

### Set upstream (if missing)

```bash
git branch -u origin/main main
```

Modern Git can use `git switch main` instead of `git checkout main`.

---

## 3. Update all local branches to match their remotes

Git has no single command to update every local branch. Use a loop: for each local branch with an **upstream**, switch to it and fast-forward (or rebase).

### Fast-forward only (recommended)

Predictable: no surprise merge commits; branches that cannot fast-forward are skipped.

```bash
git fetch --all --prune

for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  upstream=$(git rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null) || continue
  git switch "$branch"
  git merge --ff-only "$upstream" || echo "SKIP $branch: cannot fast-forward; resolve manually"
done
```

- Branches **without** a configured upstream are skipped.
- Local-only branches (no tracking remote) are unchanged.

### Rebase each branch on its upstream

Rewrites local-only commits on each branch. Abort and skip on failure.

```bash
git fetch --all --prune

for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  upstream=$(git rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null) || continue
  git switch "$branch"
  git rebase "$upstream" || { git rebase --abort; echo "SKIP $branch: rebase failed"; }
done
```

---

## Fork workflow (upstream)

After `git fetch --all --prune`, merge or rebase **upstream** into your default branch, for example:

```bash
git checkout main
git merge --ff-only upstream/main
```

Use your team’s policy (direct merge vs integration branch).

---

## Before you run bulk updates

1. **Clean working tree**: commit or stash; check with `git status`.
2. **Destructive “match remote exactly”** (drops local-only commits on a branch) — only when intentional:

   ```bash
   git fetch origin --prune
   git switch BRANCH
   git reset --hard origin/BRANCH
   ```

---

## Summary

1. `git fetch --all --prune`
2. On your main line of work: `git merge --ff-only origin/main` **or** `git rebase origin/main`
3. Run the loop in §3 to refresh every tracked local branch
