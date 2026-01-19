---
name: "done"
description: "Complete the current PR workflow by merging, switching to main, pulling changes, and running compact."
---

# /done - Complete PR Workflow

This command finalizes your PR workflow by:

1. **Merging the PR** (if it exists and isn't already merged)
2. **Switching to main branch**
3. **Pulling the latest changes**
4. **Resolving any conflicts** (if possible)
5. **Running /compact** to consolidate conversation history

## Usage

```
/done
```

## Workflow Steps

### Step 1: Check and Merge PR

First, check if there's an open PR for the current branch:

```bash
# Get current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Check if we're on a feature branch (Angular-style: feat/, fix/, etc.)
if [[ "$current_branch" =~ ^(build|ci|docs|feat|fix|perf|refactor|test)/ ]]; then
    # Check for open PR
    pr_number=$(gh pr list --head "$current_branch" --json number --jq '.[0].number' 2>/dev/null)

    if [[ -n "$pr_number" ]]; then
        # Check PR status
        pr_state=$(gh pr view "$pr_number" --json state --jq '.state')

        if [[ "$pr_state" == "OPEN" ]]; then
            echo "Merging PR #$pr_number..."
            gh pr merge "$pr_number" --squash --delete-branch
        elif [[ "$pr_state" == "MERGED" ]]; then
            echo "PR #$pr_number is already merged."
        fi
    fi
fi
```

### Step 2: Switch to Main Branch

```bash
# Get the default branch (main or master)
default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d: -f2 | tr -d ' ')
if [[ -z "$default_branch" ]]; then
    default_branch="main"
fi

git checkout "$default_branch"
```

### Step 3: Pull Latest Changes

```bash
git pull origin "$default_branch"
```

### Step 4: Handle Conflicts (if any)

If there are merge conflicts:

1. Attempt automatic resolution where possible
2. For remaining conflicts, show the user what files need attention
3. Provide guidance on resolving them

### Step 5: Run Compact

Finally, run the compact command to consolidate conversation history:

```
/compact
```

## Notes

- This command assumes you're using the agent-fork-join plugin workflow
- PR merge uses `--squash` by default to keep history clean
- The feature branch is automatically deleted after merge
- If the PR has merge conflicts, they must be resolved first

## Examples

### Typical workflow

```
User: Implement authentication feature
[... Claude implements the feature ...]
[... PR is created automatically ...]

User: /done
[Claude merges PR, switches to main, pulls, and compacts]
```

### When PR is already merged

```
User: /done
"PR #42 is already merged. Switching to main and pulling changes..."
```

## Error Handling

- If no PR exists: Switches directly to main
- If PR has conflicts: Reports conflicts and suggests resolution
- If merge fails: Reports the error and suggests manual intervention
