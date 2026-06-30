#!/bin/bash
# Git Fork Workflow - Main Script
# Handles: sync upstream, squash commits, rebase, and prepare for PR

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get repo directory
REPO_DIR="${1:-.}"
if [[ ! -d "$REPO_DIR" ]]; then
    echo -e "${RED}Error: Directory not found${NC}"
    exit 1
fi

cd "$REPO_DIR" || exit 1
REPO_DIR=$(pwd)

# Check if git repo
if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Not a git repository${NC}"
    exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Git Fork Workflow                        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Repository: ${BLUE}$(basename "$REPO_DIR")${NC}"
echo ""

# Helper functions
ask_yes_no() {
    while true; do
        read -p "$(echo -e ${GREEN}$1 [y/n]: ${NC})" yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Detect main branch
main_branch="main"
if git show-ref --verify --quiet refs/heads/master; then
    main_branch="master"
fi

# ═══════════════════════════════════════════════════
# STEP 1: Check upstream configuration
# ═══════════════════════════════════════════════════
echo -e "${BLUE}▶ Step 1: Checking Remote Configuration${NC}"
echo ""
git remote -v

if ! git remote | grep -q "^upstream$"; then
    echo -e "${YELLOW}⚠️  Upstream not configured${NC}"
    echo ""
    if ask_yes_no "Add upstream remote now?"; then
        read -p "$(echo -e ${GREEN}Enter upstream repository URL: ${NC})" upstream_url
        git remote add upstream "$upstream_url"
        echo -e "${GREEN}✓ Upstream added${NC}"
    else
        echo -e "${RED}Cannot continue without upstream${NC}"
        exit 1
    fi
fi
echo ""

# ═══════════════════════════════════════════════════
# STEP 2: Fetch latest changes
# ═══════════════════════════════════════════════════
echo -e "${BLUE}▶ Step 2: Fetching Latest Changes${NC}"
git fetch --all --prune
echo -e "${GREEN}✓ Fetched from all remotes${NC}"
echo ""

# ═══════════════════════════════════════════════════
# STEP 3: Check current status
# ═══════════════════════════════════════════════════
echo -e "${BLUE}▶ Step 3: Current Status${NC}"
current_branch=$(git branch --show-current)
echo -e "Current branch: ${CYAN}$current_branch${NC}"
echo ""

# Stash uncommitted changes if any
stashed=false
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${YELLOW}⚠️  Uncommitted changes detected${NC}"
    if ask_yes_no "Stash changes temporarily?"; then
        git stash push -u -m "Auto-stash by workflow $(date)"
        stashed=true
        echo -e "${GREEN}✓ Changes stashed${NC}"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════
# STEP 4: Sync main branch with upstream
# ═══════════════════════════════════════════════════
echo -e "${BLUE}▶ Step 4: Sync Main Branch${NC}"
echo ""

git checkout $main_branch
echo "Pulling from upstream/$main_branch..."
git pull upstream $main_branch
echo "Pushing to origin/$main_branch..."
git push origin $main_branch
echo -e "${GREEN}✓ Main branch synced${NC}"
echo ""

# ═══════════════════════════════════════════════════
# STEP 5: Analyze feature branches
# ═══════════════════════════════════════════════════
echo -e "${BLUE}▶ Step 5: Feature Branches${NC}"
echo ""

# Get feature branches
feature_branches=$(git branch | grep -v "^\*" | grep -v "^  $main_branch$" | sed 's/^  //')

if [[ -z "$feature_branches" ]]; then
    echo "No feature branches found."
    echo ""
    echo -e "${GREEN}✓ Repository is clean and synced!${NC}"
    exit 0
fi

# Show all feature branches
echo "Found feature branches:"
for branch in $feature_branches; do
    commits=$(git rev-list --count $main_branch..$branch 2>/dev/null || echo "0")
    echo -e "  ${CYAN}$branch${NC} - $commits commits ahead of $main_branch"
done
echo ""

# Return to current branch if it exists
if git show-ref --verify --quiet refs/heads/$current_branch; then
    git checkout $current_branch
fi

# ═══════════════════════════════════════════════════
# STEP 6: Work on current branch (if not main)
# ═══════════════════════════════════════════════════
if [[ "$current_branch" == "$main_branch" ]]; then
    echo -e "${YELLOW}You're on $main_branch${NC}"
    echo "Create a feature branch to start work:"
    echo "  git checkout -b feature/your-branch-name"
    echo ""
    exit 0
fi

echo -e "${BLUE}▶ Step 6: Prepare Branch for PR: ${CYAN}$current_branch${NC}"
echo ""

# Show commits on this branch
echo "Commits on this branch:"
git log --oneline $main_branch..HEAD
echo ""

commits_count=$(git rev-list --count $main_branch..HEAD)

# Check if commits need squashing
if [[ $commits_count -gt 1 ]]; then
    echo -e "${YELLOW}⚠️  $commits_count commits detected${NC}"
    echo ""
    if ask_yes_no "Squash commits into one?"; then
        # Rebase and squash
        GIT_SEQUENCE_EDITOR="sed -i '' -e '2,\$s/^pick/squash/'" git rebase -i $main_branch
        echo -e "${GREEN}✓ Commits squashed${NC}"
        echo ""
    fi
fi

# Rebase on latest main
echo "Rebasing on latest $main_branch..."
git rebase $main_branch
echo -e "${GREEN}✓ Rebased on $main_branch${NC}"
echo ""

# Show final commit
echo "Final commit:"
git log -1 --oneline
echo ""

# Ask to push
if ask_yes_no "Push to your fork (origin)?"; then
    # Check if branch has upstream
    if git rev-parse --abbrev-ref @{upstream} >/dev/null 2>&1; then
        echo -e "${YELLOW}Branch exists on origin. Force push required.${NC}"
        git push --force-with-lease origin $current_branch
    else
        git push -u origin $current_branch
    fi
    echo -e "${GREEN}✓ Pushed to origin${NC}"
    echo ""

    # Show PR link
    origin_url=$(git remote get-url origin | sed 's/\.git$//' | sed 's/git@github.com:/https:\/\/github.com\//')
    if [[ $origin_url == *"github.com"* ]]; then
        echo -e "${CYAN}Open PR:${NC}"
        echo "$origin_url/compare/$current_branch?expand=1"
        echo ""
    fi
fi

# Restore stashed changes
if [[ "$stashed" == "true" ]]; then
    if ask_yes_no "Restore stashed changes?"; then
        git stash pop
        echo -e "${GREEN}✓ Changes restored${NC}"
    fi
fi

echo ""
echo -e "${GREEN}✓ Workflow complete!${NC}"
echo ""
