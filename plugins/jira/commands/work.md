---
name: "work"
description: "Start working on a JIRA ticket. Lists available tickets and sets up tracking for smart commits."
---

# /jira:work Command

Start working on a JIRA ticket. This command lists available tickets from JIRA, allows selection, and sets up local tracking for smart commits integration.

## When This Command Is Invoked

Execute the following steps in order:

### Step 1: Check Prerequisites

Verify JIRA is configured:

```bash
# Check beads JIRA config
jira_url=$(bd config get jira.url 2>/dev/null || echo "")
jira_project=$(bd config get jira.project 2>/dev/null || echo "")

if [[ -z "$jira_url" || -z "$jira_project" ]]; then
    echo "JIRA not configured. Run /jira:setup first."
    exit 1
fi
```

### Step 2: Sync with JIRA

Pull latest tickets from JIRA:

```bash
bd jira sync --pull
```

### Step 3: Get Current User

Get the current user's JIRA username for prioritizing assigned tickets:

```bash
jira_username=$(bd config get jira.username 2>/dev/null || echo "")
```

### Step 4: Fetch Available Tickets

Use beads to list JIRA tickets. Prioritize tickets assigned to the current user:

```bash
# List issues from beads (synced from JIRA)
# Filter by: open status, optionally by label if configured
bd list --status=open --format=json
```

Parse the tickets and organize them:

1. **Assigned to user** - List first
2. **Unassigned or assigned to others** - List after

### Step 5: Present Ticket Selection

Use the AskUserQuestion tool to present tickets to the user.

**Format each ticket option as:**

```
[TICKET-123] Summary of the ticket (Assignee: user@email.com)
```

**Ordering:**

1. If a prompt/context is provided, attempt to guess the most relevant ticket based on:
   - Keyword matching in ticket summary/description
   - Tickets assigned to current user
2. Put the guessed "best match" first with "(Recommended)" suffix
3. List remaining tickets assigned to user
4. List other open tickets

**Example question:**

- Header: "Ticket"
- Question: "Which JIRA ticket are you working on?"
- Options (up to 4, with "Other" always available):
  - "PGF-123: Implement login feature (Recommended)"
  - "PGF-456: Fix authentication bug"
  - "PGF-789: Update documentation"
  - "Other" (user can specify ticket ID manually)

### Step 6: Find Beads Issue ID

Map the selected JIRA ticket key to its beads issue ID:

```bash
JIRA_KEY="PGF-123"  # Selected JIRA ticket

# Find beads issue that has this JIRA key in external_ref
BEADS_ISSUE=$(bd list --json 2>/dev/null | jq -r ".[] | select(.external_ref | contains(\"$JIRA_KEY\")) | .id" | head -1)

if [[ -z "$BEADS_ISSUE" || "$BEADS_ISSUE" == "null" ]]; then
    echo "Error: Could not find beads issue for JIRA ticket $JIRA_KEY"
    echo "Try running 'bd jira sync --pull' and try again."
    exit 1
fi

# Get issue details from beads
ISSUE_TITLE=$(bd show "$BEADS_ISSUE" --json | jq -r '.title // empty')
JIRA_URL=$(bd show "$BEADS_ISSUE" --json | jq -r '.external_ref // empty')
```

### Step 7: Set Beads Current Issue

Set the current beads issue for tracking (agent-fork-join uses this):

```bash
# The .beads directory should already exist (created by bd init)
# Write the beads issue ID to current-issue file
echo "$BEADS_ISSUE" > .beads/current-issue
```

**Note:** We use the **beads issue ID** (e.g., `bd-100`) for tracking, not the JIRA key. The beads issue contains the JIRA URL in its `external_ref` field.

### Step 8: Show Confirmation

Display confirmation and next steps:

```
=== Now Working On ===

Beads Issue: bd-100
JIRA Ticket: PGF-123
Summary:     Implement login feature
URL:         https://badal.atlassian.net/browse/PGF-123

Current issue set: .beads/current-issue -> bd-100

Smart commits are now enabled. All commits will include "PGF-123" for JIRA integration.

When done, run /done to:
- Complete the PR workflow
- Update issue status (syncs to JIRA)
- Clean up tracking files
```

## Error Handling

### JIRA not configured

```
JIRA integration not configured.

Run /jira:setup to configure JIRA integration first.
```

### No open tickets found

```
No open tickets found matching your criteria.

Check JIRA directly: https://badal.atlassian.net/browse/PGF
Or create a new ticket and run /jira:work again.
```

### Ticket not found

If user enters a ticket ID manually that doesn't exist:

```
Ticket PGF-999 not found in JIRA.

Please verify the ticket ID and try again.
```

## Integration with agent-fork-join

When `.beads/current-issue` exists:

1. **Commits**: Include JIRA ticket ID in commit message (e.g., "PGF-123: Add login form")
   - The JIRA key is extracted from the beads issue's `external_ref` field
2. **PRs**: Include ticket ID in PR title and link in description
3. **Smart Commits**: JIRA will automatically link commits/PRs to the ticket
4. **Status Updates**: Issue status changes via beads are synced to JIRA
