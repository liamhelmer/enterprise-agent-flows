---
name: "done"
description: "Complete the current PR workflow: merge PR, switch to main, pull changes, resolve conflicts, and run compact."
---

# /done Command

Complete the current PR workflow by merging, switching to main, and cleaning up.

## When This Command Is Invoked

Execute the following steps in order:

### Step 1: Check Current State

Run these commands to understand the current state:

```bash
# Get current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $current_branch"

# Get default branch
default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d: -f2 | tr -d ' ' || echo "main")
echo "Default branch: $default_branch"
```

### Step 2: Merge PR or Detect Already Merged

If on a feature branch (feat/, fix/, etc.), check PR state and handle accordingly:

```bash
# Check if current branch is a feature branch
if [[ "$current_branch" =~ ^(build|ci|docs|feat|fix|perf|refactor|test)/ ]]; then
    # Get PR number (including merged/closed PRs)
    pr_number=$(gh pr list --head "$current_branch" --state all --json number --jq '.[0].number' 2>/dev/null || echo "")

    if [[ -n "$pr_number" ]]; then
        # Check PR state
        pr_state=$(gh pr view "$pr_number" --json state --jq '.state')

        case "$pr_state" in
        "OPEN")
            echo "Merging PR #$pr_number..."
            gh pr merge "$pr_number" --squash --delete-branch
            # Mark branch for local deletion
            ;;
        "MERGED")
            echo "PR #$pr_number is already merged"
            # Mark branch for local deletion
            ;;
        "CLOSED")
            echo "PR #$pr_number is closed (not merged)"
            ;;
        esac
    else
        echo "No PR found for this branch"
    fi
fi
```

### Step 3: Switch to Main Branch

```bash
# Stash any uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
    git stash push -m "Auto-stash before /done"
fi

# Switch to default branch
git checkout "$default_branch"
```

### Step 4: Pull Latest Changes

```bash
git pull origin "$default_branch"
```

If there are merge conflicts:

1. First try to auto-resolve by accepting remote changes: `git checkout --theirs . && git add -A`
2. If that fails, show the user the conflicting files and ask them to resolve manually

### Step 5: Delete Local Feature Branch

If the PR was merged (either just now or previously), delete the local feature branch:

```bash
# Delete local branch if it was marked for deletion
if [[ -n "$branch_to_delete" ]]; then
    git branch -D "$branch_to_delete"
    # Also clean up remote tracking branch
    git branch -dr "origin/$branch_to_delete" 2>/dev/null || true
fi
```

### Step 6: Clean Up Session State

```bash
# Remove session tracking files
rm -f .fork-join/current_session
rm -f .fork-join/tracked_files.txt
```

### Step 6: Run Compact

After all steps complete successfully, run the `/compact` command to consolidate conversation history.

## Error Handling

- **PR has merge conflicts**: Tell the user they need to resolve conflicts on the PR first before running /done
- **Cannot switch branches**: Check for uncommitted changes and stash them
- **Pull fails with conflicts**: Try auto-resolution first, then ask user to resolve manually if needed

## Output Format

Report progress at each step:

```
=== Completing PR Workflow ===

Checking for open PR on branch feat/my-feature...
Found open PR #42, merging with squash...
Successfully merged PR #42

Switching to main branch...
Switched to main

Pulling latest changes...
Already up to date.

=== Workflow Complete ===

Running /compact to consolidate conversation history...
```
