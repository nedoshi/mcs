# Git Fork Workflow - Complete Guide

Simple tools to manage git forks without getting stuck with divergent branches.

---

## 📦 What You Have

**3 Simple Scripts:**

1. **`workflow.sh`** - Sync upstream, squash commits, rebase (use daily)
2. **`cleanup.sh`** - Delete branches with merged PRs (use after PR merges)
3. **`install.sh`** - Install scripts system-wide (optional)

**This README** - Everything you need to know

---

## 🎯 The Problem These Tools Solve

- ❌ Divergent branches blocking PRs
- ❌ Confusion between local, origin (fork), and upstream (team repo)
- ❌ Multiple commits that should be one
- ❌ Out-of-sync main branches
- ❌ Leftover branches after PRs merge

---

## 🚀 Quick Start

### Before Starting Work (Daily)

```bash
cd /Users/flyers/Documents/Code/git-sync
./workflow.sh /Users/flyers/Documents/GitHub/poc-guides
```

This will:
1. ✅ Check upstream is configured
2. ✅ Fetch latest changes
3. ✅ Sync your main with upstream/main
4. ✅ Show status of all branches
5. ✅ Help squash commits if needed
6. ✅ Rebase on latest main
7. ✅ Push to your fork

### After Your PR Merges

```bash
cd /Users/flyers/Documents/Code/git-sync
./cleanup.sh /Users/flyers/Documents/GitHub/poc-guides
```

This will:
1. ✅ Find all merged PRs
2. ✅ Show which branches to delete
3. ✅ Delete from local and your fork

---

## 📖 Understanding the Setup

```
┌─────────────────────┐
│   UPSTREAM          │  ← Team's main repo
│   rh-mobb/          │     (you open PRs here)
│   poc-guides        │
└──────────┬──────────┘
           │
           │ (you forked it)
           ↓
┌─────────────────────┐
│   ORIGIN            │  ← Your fork
│   nedoshi/          │     (you push here)
│   poc-guides        │
└──────────┬──────────┘
           │
           │ (you cloned it)
           ↓
┌─────────────────────┐
│   LOCAL             │  ← Your machine
│   ~/Documents/      │     (you work here)
│   GitHub/poc-guides │
└─────────────────────┘
```

---

## 📋 Complete Workflow

### 1. Starting New Work

```bash
# Sync everything
./workflow.sh /Users/flyers/Documents/GitHub/poc-guides

# Create feature branch
cd /Users/flyers/Documents/GitHub/poc-guides
git checkout -b ndguide-issue-95

# Make your changes
vim file.md
git add file.md
git commit -m "Add feature"

# More changes (multiple commits are OK)
git commit -m "Fix typo"
git commit -m "Update docs"
```

### 2. Before Opening a PR

```bash
# Run workflow again - it will squash commits
./workflow.sh /Users/flyers/Documents/GitHub/poc-guides

# Follow the prompts:
# - It detects multiple commits
# - Asks if you want to squash (say yes)
# - Squashes into 1 commit
# - Rebases on latest main
# - Asks to push (say yes)

# Copy the PR link it shows
```

### 3. After PR is Merged

```bash
# Clean up the merged branch
./cleanup.sh /Users/flyers/Documents/GitHub/poc-guides

# It will:
# - Show merged PRs
# - Ask to delete branches
# - Delete from local and origin
```

---

## 🎮 Script Details

### workflow.sh

**When to use:** Before starting work, before opening PR

**What it does:**
- Checks upstream configuration (adds if missing)
- Fetches latest from all remotes
- Syncs main branch (upstream → local → origin)
- Shows all feature branches
- For current branch:
  - Shows commits
  - Squashes if multiple commits
  - Rebases on latest main
  - Pushes to origin
  - Shows PR link

**Usage:**
```bash
./workflow.sh /path/to/repo

# Or from within repo:
cd /path/to/repo
./workflow.sh
```

**Interactive prompts:**
- Add upstream? (if not configured)
- Stash uncommitted changes?
- Squash commits?
- Push to origin?
- Restore stashed changes?

---

### cleanup.sh

**When to use:** After PR is merged

**What it does:**
- Uses GitHub CLI to find merged PRs
- Shows which branches have merged PRs
- Asks for confirmation
- Deletes branches from local (if exist)
- Deletes branches from origin/fork (if exist)

**Usage:**
```bash
./cleanup.sh /path/to/repo
```

**Requirements:**
- GitHub CLI installed: `brew install gh`
- Authenticated: `gh auth login`

**Interactive prompts:**
- Delete these branches? (shows list first)

---

### install.sh

**When to use:** Optional - installs tools system-wide

**What it does:**
- Copies scripts to `~/.local/bin`
- Renames to `git-workflow` and `git-cleanup`
- Adds to PATH (if you confirm)

**Usage:**
```bash
./install.sh

# After install, use from anywhere:
git-workflow /path/to/repo
git-cleanup /path/to/repo
```

---

## 💡 Examples

### Example 1: Daily Workflow

```bash
# Morning: Sync everything
cd /Users/flyers/Documents/Code/git-sync
./workflow.sh /Users/flyers/Documents/GitHub/poc-guides

# Create branch for issue #95
cd /Users/flyers/Documents/GitHub/poc-guides
git checkout -b ndguide-issue-95

# Work on it
vim osd/guide.md
git add osd/guide.md
git commit -m "Add guide"

# More changes
git commit -m "Fix formatting"
git commit -m "Add examples"

# Ready for PR: squash those 3 commits
cd /Users/flyers/Documents/Code/git-sync
./workflow.sh /Users/flyers/Documents/GitHub/poc-guides

# Output shows:
# - 3 commits detected
# - Asks to squash → yes
# - Commits squashed to 1
# - Asks to push → yes
# - Shows PR link

# Open PR using the link

# After PR merges:
./cleanup.sh /Users/flyers/Documents/GitHub/poc-guides

# Output shows:
# - ndguide-issue-95 merged in PR #140
# - Asks to delete → yes
# - Deleted from origin
```

### Example 2: Fixing Divergent Branches

```bash
# You see "divergent branches" error
git status
# Output: Your branch and 'origin/branch' have diverged

# Run workflow
./workflow.sh

# It will:
# 1. Fetch latest
# 2. Rebase your branch
# 3. Ask to force push
# 4. Fixed!
```

### Example 3: Multiple Branches to Clean Up

```bash
# You have 5 merged PRs
./cleanup.sh /Users/flyers/Documents/GitHub/poc-guides

# Output:
# PR #130: ndguide-issue-87 (merged May 13)
# PR #131: ndguide-issue-89 (merged May 13)
# PR #132: ndguide-issue-90 (merged May 13)
# PR #133: ndguide-issue-91 (merged May 13)
# PR #134: ndguide-issue-92 (merged May 14)
#
# Delete these branches? [y/n]: y
#
# ✓ Deleted remote: ndguide-issue-87
# ✓ Deleted remote: ndguide-issue-89
# ✓ Deleted remote: ndguide-issue-90
# ✓ Deleted local: ndguide-issue-91
# ✓ Deleted remote: ndguide-issue-91
# ✓ Deleted remote: ndguide-issue-92
#
# ✓ Cleaned up 6 branch reference(s)
```

---

## 🔧 Setup Requirements

### Required

1. **Git** (already installed)
2. **GitHub CLI** for cleanup script
   ```bash
   brew install gh
   gh auth login
   ```

### First Time Setup

1. **Configure upstream** (workflow.sh will prompt if missing)
   ```bash
   cd /Users/flyers/Documents/GitHub/poc-guides
   git remote add upstream https://github.com/rh-mobb/poc-guides.git
   ```

2. **Test it**
   ```bash
   ./workflow.sh /Users/flyers/Documents/GitHub/poc-guides
   ```

---

## 🆘 Troubleshooting

### "Error: Not a git repository"

Make sure you're pointing to a git repo:
```bash
./workflow.sh /Users/flyers/Documents/GitHub/poc-guides
```

### "Upstream not configured"

The script will prompt you to add it. Get the upstream URL from your team:
```
https://github.com/rh-mobb/poc-guides.git
```

### "GitHub CLI required"

For cleanup script:
```bash
brew install gh
gh auth login
```

### "Divergent branches"

This is exactly what `workflow.sh` fixes! Just run it:
```bash
./workflow.sh
```

### Squash failed / merge conflicts

If squashing fails during workflow:
```bash
# Abort the rebase
git rebase --abort

# Check what happened
git log --oneline

# Try manual squash
git rebase -i main
```

### Can't delete branch "not fully merged"

The branch might not be in upstream yet. Check:
```bash
# See if your commits are in upstream
git log upstream/main --oneline | head -20

# If you see your commits, force delete
git branch -D branch-name
git push origin --delete branch-name
```

---

## 🎓 Understanding What the Scripts Do

### workflow.sh Step-by-Step

```bash
# 1. Check remotes
git remote -v

# 2. Fetch latest
git fetch --all --prune

# 3. Sync main
git checkout main
git pull upstream main
git push origin main

# 4. Return to your branch
git checkout your-branch

# 5. Squash commits (if multiple)
git rebase -i main
# Changes: pick → squash for all but first commit

# 6. Rebase on main
git rebase main

# 7. Push to fork
git push --force-with-lease origin your-branch
```

### cleanup.sh Step-by-Step

```bash
# 1. Fetch latest
git fetch --all --prune

# 2. Update main
git checkout main
git pull upstream main

# 3. Find merged PRs
gh pr list --repo upstream-repo --state merged --author @me

# 4. For each merged PR branch:
#    - Delete local: git branch -D branch-name
#    - Delete remote: git push origin --delete branch-name
```

---

## 📊 Quick Reference

### Daily Commands

```bash
# Before work
./workflow.sh /path/to/repo

# After PR merge
./cleanup.sh /path/to/repo
```

### Manual Git Commands

If you want to do things manually:

```bash
# Sync main
git checkout main
git pull upstream main
git push origin main

# Squash commits (last 3)
git rebase -i HEAD~3

# Rebase on main
git checkout your-branch
git rebase main

# Force push
git push --force-with-lease origin your-branch

# Delete branch
git branch -d branch-name
git push origin --delete branch-name
```

---

## ✅ Best Practices

1. **Run workflow.sh before starting work**
   - Keeps everything synced
   - Prevents divergent branches

2. **Commit often while working**
   - Many small commits = good for you
   - workflow.sh will squash them before PR

3. **Run workflow.sh before opening PR**
   - Squashes commits
   - Rebases on latest main
   - Ensures clean PR

4. **Run cleanup.sh after PR merges**
   - Keeps your fork clean
   - Deletes old branches

5. **One branch per issue**
   - Use descriptive names: `ndguide-issue-95`
   - Delete after merge

---

## 🎯 Summary

**3 Scripts:**
- `workflow.sh` - Use before work and before PR
- `cleanup.sh` - Use after PR merges
- `install.sh` - Optional system-wide install

**1 Workflow:**
```
1. workflow.sh (sync)
2. Create branch
3. Work and commit
4. workflow.sh (squash & push)
5. Open PR
6. Wait for merge
7. cleanup.sh (delete branch)
```

**You'll never have:**
- ❌ Divergent branches
- ❌ Multiple commits in PR
- ❌ Out-of-sync repos
- ❌ Old merged branches cluttering your fork

---

## 📞 Quick Help

```bash
# Show remotes
git remote -v

# Show branches
git branch -a

# Show commits on branch
git log main..HEAD --oneline

# Check if branch is merged
git branch --merged upstream/main

# Force delete branch
git branch -D branch-name
git push origin --delete branch-name
```

---

**That's it! You now have everything to manage git forks like a pro.** 🚀
