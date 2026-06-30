#!/bin/bash
# Git Cleanup - Delete Merged Branches
# Deletes branches that have been merged to upstream

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get repo directory
REPO_DIR="${1:-.}"
cd "$REPO_DIR" 2>/dev/null || exit 1

echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Git Cleanup Merged Branches              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for git repo
if [[ ! -d ".git" ]]; then
    echo -e "${RED}Error: Not a git repository${NC}"
    exit 1
fi

# Check for GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI required${NC}"
    echo "Install: brew install gh"
    echo "Then run: gh auth login"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub${NC}"
    echo "Run: gh auth login"
    exit 1
fi

# Check for upstream
if ! git remote | grep -q "^upstream$"; then
    echo -e "${RED}Error: No upstream configured${NC}"
    exit 1
fi

# Detect main branch
main_branch="main"
if git show-ref --verify --quiet refs/heads/master; then
    main_branch="master"
fi

# Get upstream repo name
upstream_repo=$(git remote get-url upstream | sed 's/.*github.com[:/]\(.*\)\.git/\1/' | sed 's/.*github.com[:/]\(.*\)/\1/')

echo "Fetching latest..."
git fetch --all --prune 2>&1 | grep -v "^From"
echo ""

# Update main
git checkout $main_branch >/dev/null 2>&1
git pull upstream $main_branch >/dev/null 2>&1
git push origin $main_branch >/dev/null 2>&1
echo -e "${GREEN}✓ Main branch updated${NC}"
echo ""

# Get merged PRs
echo "Checking merged PRs..."
merged_prs=$(gh pr list --repo "$upstream_repo" --state merged --author @me --limit 50 --json number,headRefName,title,mergedAt 2>/dev/null)

if [[ -z "$merged_prs" ]] || [[ "$merged_prs" == "[]" ]]; then
    echo -e "${GREEN}No merged PRs found - nothing to clean up${NC}"
    exit 0
fi

# Parse and display
echo ""
echo -e "${YELLOW}Merged PRs:${NC}"
echo ""

branches_to_delete=()

echo "$merged_prs" | jq -r '.[] | "\(.number)|\(.headRefName)|\(.title)|\(.mergedAt)"' | while IFS='|' read -r pr_number branch_name pr_title merged_at; do
    # Skip main branch
    if [[ "$branch_name" == "$main_branch" ]]; then
        continue
    fi

    merged_date=$(echo "$merged_at" | cut -d'T' -f1)

    # Check if branch still exists
    local_exists=$(git show-ref --verify --quiet refs/heads/$branch_name 2>/dev/null && echo "yes" || echo "no")
    remote_exists=$(git ls-remote --heads origin $branch_name 2>/dev/null | grep -q "$branch_name" && echo "yes" || echo "no")

    if [[ "$local_exists" == "yes" ]] || [[ "$remote_exists" == "yes" ]]; then
        echo -e "${CYAN}PR #$pr_number${NC}: $branch_name"
        echo "  Title: $pr_title"
        echo "  Merged: $merged_date"

        if [[ "$local_exists" == "yes" ]]; then
            echo -e "  ${BLUE}→ Exists locally${NC}"
        fi
        if [[ "$remote_exists" == "yes" ]]; then
            echo -e "  ${YELLOW}→ Exists on origin${NC}"
        fi
        echo ""

        # Save for deletion
        echo "$branch_name" >> /tmp/branches_to_delete_$$.txt
    fi
done

# Check if there's anything to delete
if [[ ! -f /tmp/branches_to_delete_$$.txt ]]; then
    echo -e "${GREEN}All merged branches already cleaned up!${NC}"
    exit 0
fi

branches_to_delete=$(cat /tmp/branches_to_delete_$$.txt)
rm /tmp/branches_to_delete_$$.txt

echo -e "${RED}These branches will be deleted:${NC}"
echo "$branches_to_delete" | sed 's/^/  - /'
echo ""

read -p "$(echo -e ${GREEN}Delete these branches? [y/n]: ${NC})" confirm
if [[ ! "$confirm" =~ ^[Yy] ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""
deleted_count=0

for branch in $branches_to_delete; do
    # Delete local if exists
    if git show-ref --verify --quiet refs/heads/$branch 2>/dev/null; then
        git branch -D $branch >/dev/null 2>&1
        echo -e "${GREEN}✓${NC} Deleted local: $branch"
        ((deleted_count++))
    fi

    # Delete remote if exists
    if git ls-remote --heads origin $branch 2>/dev/null | grep -q "$branch"; then
        git push origin --delete $branch >/dev/null 2>&1
        echo -e "${GREEN}✓${NC} Deleted remote: $branch"
        ((deleted_count++))
    fi
done

echo ""
echo -e "${GREEN}✓ Cleaned up $deleted_count branch reference(s)${NC}"
echo ""
