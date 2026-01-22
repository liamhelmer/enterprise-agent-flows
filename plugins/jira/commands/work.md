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

### Step 6: Set Up .jira Directory

Create the .jira directory:

```bash
# Create .jira directory if it doesn't exist
mkdir -p .jira
```

### Step 7: Create Ticket Tracking File

Create a file for the selected ticket and symlink:

```bash
TICKET_ID="PGF-123"  # Selected ticket

# Create ticket file with metadata
cat > ".jira/$TICKET_ID" << EOF
ticket_id=$TICKET_ID
started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
summary=Implement login feature
url=https://badal.atlassian.net/browse/$TICKET_ID
EOF

# Create/update symlink to current ticket
ln -sf "$TICKET_ID" .jira/current-ticket
```

### Step 8: Show Confirmation

Display confirmation and next steps:

```
=== Now Working On ===

Ticket:  PGF-123
Summary: Implement login feature
URL:     https://badal.atlassian.net/browse/PGF-123

Tracking file created: .jira/PGF-123
Current ticket linked: .jira/current-ticket -> PGF-123

Smart commits are now enabled. All commits will include "PGF-123" for JIRA integration.

When done, run /done to:
- Complete the PR workflow
- Update JIRA ticket status
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

When `.jira/current-ticket` exists:

1. **Commits**: Include ticket ID in commit message (e.g., "PGF-123: Add login form")
2. **PRs**: Include ticket ID in PR title and link in description
3. **Smart Commits**: JIRA will automatically link commits/PRs to the ticket
