---
name: "work"
description: "Start working on a JIRA ticket. Lists available tickets and sets up tracking for smart commits."
---

# /jira:work Command

Start working on a JIRA ticket. This command accepts an optional ticket ID argument, or lists available tickets from JIRA for selection.

## Usage

```
/jira:work [TICKET-ID]
```

**Examples:**

- `/jira:work PGF-369` - Start working on PGF-369 directly
- `/jira:work` - List available tickets for selection

## When This Command Is Invoked

Execute the following steps in order:

### Step 1: Check Prerequisites and Load/Create Cache

Verify JIRA is configured and create/update the config cache for fast lookups:

```bash
# Check if cache exists and is recent (less than 1 hour old)
CACHE_FILE=".jira/config.cache"
CACHE_MAX_AGE=3600  # 1 hour in seconds

if [[ -f "$CACHE_FILE" ]]; then
    cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null)))
    if [[ $cache_age -lt $CACHE_MAX_AGE ]]; then
        # Use cached values
        source "$CACHE_FILE"
    fi
fi

# If cache is missing or stale, refresh from beads config
if [[ -z "$JIRA_URL" || -z "$JIRA_PROJECT" ]]; then
    JIRA_URL=$(bd config get jira.url 2>/dev/null || echo "")
    JIRA_PROJECT=$(bd config get jira.project 2>/dev/null || echo "")
    JIRA_USERNAME=$(bd config get jira.username 2>/dev/null || echo "")
    JIRA_LABEL=$(bd config get jira.label 2>/dev/null || echo "")

    if [[ -z "$JIRA_URL" || -z "$JIRA_PROJECT" ]]; then
        echo "JIRA not configured. Run /jira:setup first."
        exit 1
    fi

    # Create .jira directory and write cache
    mkdir -p .jira
    cat > "$CACHE_FILE" << EOF
# JIRA config cache - auto-generated, do not edit
# Refreshed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# NOTE: JIRA_API_TOKEN is NEVER stored here - use environment variable
JIRA_URL="$JIRA_URL"
JIRA_PROJECT="$JIRA_PROJECT"
JIRA_USERNAME="$JIRA_USERNAME"
JIRA_LABEL="$JIRA_LABEL"
EOF
fi
```

**SECURITY NOTE:** The JIRA API token is NEVER stored in cache files or beads. It must always be provided via the `JIRA_API_TOKEN` environment variable.

### Step 2: Check for Ticket Argument

If a ticket ID was provided as an argument, skip ticket selection:

```bash
TICKET_ARG="$1"  # First argument to the command

if [[ -n "$TICKET_ARG" ]]; then
    # Normalize ticket ID (add project prefix if missing)
    if [[ "$TICKET_ARG" =~ ^[0-9]+$ ]]; then
        JIRA_KEY="${JIRA_PROJECT}-${TICKET_ARG}"
    else
        JIRA_KEY="$TICKET_ARG"
    fi
    echo "Using ticket: $JIRA_KEY"
    # Skip to Step 4 (sync) then Step 6 (find beads issue)
fi
```

### Step 3: Sync with JIRA (if no argument or ticket not found locally)

Pull latest tickets from JIRA:

```bash
bd jira sync --pull
```

### Step 4: Ticket Selection (only if no argument provided)

If no ticket argument was provided, present ticket selection to user:

**Use beads to list tickets with jq filtering:**

```bash
# Get tickets prioritized by assignee, limited to 8 for performance
bd list --status=open --json 2>/dev/null | jq -r --arg user "$JIRA_USERNAME" \
  '[.[] | select(.status == "open" or .status == "in_progress")]
   | sort_by(if .assignee == $user then 0 else 1 end)
   | .[:8]
   | .[]
   | "\(.id)|\(.external_ref // "" | sub(".*/browse/"; ""))|\(.title // "No title")|\(.assignee // "unassigned")"'
```

Use AskUserQuestion to present tickets (up to 4 options).

### Step 5: Find Beads Issue ID

Map the selected/provided JIRA ticket key to its beads issue ID:

```bash
# Find beads issue using jq --arg for safe injection and 'first' for efficiency
BEADS_ISSUE=$(bd list --json 2>/dev/null | jq -r --arg key "$JIRA_KEY" \
  'first(.[] | select(.external_ref != null and (.external_ref | contains($key))) | .id) // empty')

if [[ -z "$BEADS_ISSUE" || "$BEADS_ISSUE" == "null" ]]; then
    echo "Error: Could not find beads issue for JIRA ticket $JIRA_KEY"
    echo "Try running 'bd jira sync --pull' and try again."
    exit 1
fi

# Get issue details (single bd show call)
ISSUE_JSON=$(bd show "$BEADS_ISSUE" --json 2>/dev/null)
ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title // empty')
ISSUE_STATUS=$(echo "$ISSUE_JSON" | jq -r '.status // "open"')
FULL_JIRA_URL=$(echo "$ISSUE_JSON" | jq -r '.external_ref // empty')
```

### Step 6: Set Current Issue and Create Ticket Cache

Set up tracking files for fast hook access:

```bash
# Write beads issue ID for agent-fork-join
echo "$BEADS_ISSUE" > .beads/current-issue

# Create ticket cache for fast hook lookups (no bd calls needed)
mkdir -p .jira
cat > ".jira/current-ticket.cache" << EOF
# Current ticket cache - auto-generated
# NOTE: JIRA_API_TOKEN is NEVER stored here
BEADS_ISSUE="$BEADS_ISSUE"
JIRA_KEY="$JIRA_KEY"
JIRA_URL="$FULL_JIRA_URL"
ISSUE_TITLE="$ISSUE_TITLE"
ISSUE_STATUS="$ISSUE_STATUS"
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
```

### Step 7: Show Confirmation

Display confirmation:

```
=== Now Working On ===

Beads Issue: bd-100
JIRA Ticket: PGF-123
Summary:     Implement login feature
URL:         https://badal.atlassian.net/browse/PGF-123
Status:      open

Cached config: .jira/config.cache
Cached ticket: .jira/current-ticket.cache
Current issue: .beads/current-issue

Smart commits enabled. Status will be set to "In Progress" on first prompt.

When done, run /done to complete the PR workflow.
```

## Auto-Set "In Progress" Status

When a prompt is submitted with a ticket set, the `on-prompt-submit` hook will:

1. Read `.jira/current-ticket.cache` (fast, no bd calls)
2. Check if `ISSUE_STATUS` is not "in_progress"
3. If so, update the status via beads and sync to JIRA
4. Update the cache with the new status

This ensures the ticket is automatically marked "In Progress" when you start working.

## Error Handling

### JIRA not configured

```
JIRA integration not configured.

Run /jira:setup to configure JIRA integration first.
```

### Ticket not found

```
Ticket PGF-999 not found in beads.

Try running 'bd jira sync --pull' to refresh from JIRA.
```

## Cache Files

| File                         | Purpose                     | Security          |
| ---------------------------- | --------------------------- | ----------------- |
| `.jira/config.cache`         | JIRA URL, project, username | Safe (no secrets) |
| `.jira/current-ticket.cache` | Current ticket details      | Safe (no secrets) |
| `.beads/current-issue`       | Beads issue ID              | Safe              |

**NEVER STORED:** `JIRA_API_TOKEN` - always use environment variable.

## Integration with agent-fork-join

When `.beads/current-issue` exists:

1. **Commits**: Include JIRA ticket ID (read from cache)
2. **PRs**: Include ticket ID in title and link in description
3. **Auto In Progress**: Status set on first prompt
4. **Status Updates**: Changes sync to JIRA via beads
