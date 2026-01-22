# JIRA Plugin

## Purpose

This plugin provides JIRA integration with beads for issue tracking, smart commits, and PR automation. It enables seamless workflow between local development and JIRA ticket management.

## Activation

The plugin activates when the user runs any `/jira:*` command.

## Commands

### /jira:setup - Configure JIRA Integration

Use `/jira:setup` to set up JIRA integration with beads.

The command will:

1. **Check Prerequisites**
   - Verify `JIRA_API_TOKEN` environment variable is set
   - Verify `bd` (beads CLI) is installed and available

2. **Get Defaults**
   - Get email from `git config --global user.email` for username default
   - Default JIRA URL: `https://badal.atlassian.net`

3. **Collect Configuration** (if prerequisites met)
   - JIRA URL: Default to https://badal.atlassian.net (allow override)
   - Project key (e.g., PGF)
   - Optional label filter (e.g., DevEx)
   - Optional JQL filter: Default to `sprint in openSprints() OR status in ("In Review", "In Progress")`
   - JIRA username: Default to git email (allow override)

4. **Setup beads**
   - Initialize beads if `.beads/` directory doesn't exist
   - Run `bd doctor --fix` to resolve any issues

5. **Configure JIRA**
   - Set `jira.url` config
   - Set `jira.project` config
   - Set `jira.label` config (if provided)
   - Set `jira.jql` config (if provided, default: active issues only)
   - Set `jira.username` config

6. **Initial Sync**
   - Run `bd jira sync --pull` to import issues from JIRA

### /jira:work - Start Working on a Ticket

Use `/jira:work [TICKET-ID]` to start working on a JIRA ticket.

**Usage:**

- `/jira:work PGF-369` - Start working on PGF-369 directly (fast)
- `/jira:work 369` - Same as above (project prefix auto-added)
- `/jira:work` - List available tickets for selection

The command will:

1. **Check Prerequisites & Cache**
   - Verify JIRA is configured (run `/jira:setup` if not)
   - Load/refresh `.jira/config.cache` for fast lookups

2. **Handle Ticket Argument (if provided)**
   - Skip ticket selection if ticket ID argument given
   - Normalize ticket ID (add project prefix if just a number)

3. **Sync with JIRA**
   - Pull latest tickets from JIRA via beads

4. **Present Ticket Selection (only if no argument)**
   - List open tickets, prioritizing those assigned to the user
   - Use jq filtering for efficient JSON processing

5. **Map JIRA to Beads Issue**
   - Find the beads issue ID from the selected JIRA ticket key
   - The beads issue contains the JIRA URL in its `external_ref` field

6. **Set Up Tracking & Cache**
   - Write the beads issue ID to `.beads/current-issue`
   - Create `.jira/current-ticket.cache` for fast hook access
   - agent-fork-join will detect these files for smart commits

7. **Offer Branch Creation (if on main)**
   - If on main/master branch, suggest creating a feature branch
   - Generate branch name from ticket: `feat/PGF-123-short-description`
   - User can: accept, edit the name, or stay on main
   - If staying on main, branch created automatically on first prompt

## Auto "In Progress" Status

When you submit a prompt with a ticket set, the hook will:

1. Read ticket status from `.jira/current-ticket.cache` (fast, no bd calls)
2. If status is not "in_progress", automatically update it
3. Sync the status change to JIRA
4. Update the cache with new status

This ensures tickets are automatically marked "In Progress" when you start working.

## Caching for Fast Lookups

To minimize latency, the plugin caches JIRA config and ticket data locally:

| File                         | Purpose                | Contents                               |
| ---------------------------- | ---------------------- | -------------------------------------- |
| `.jira/config.cache`         | JIRA config (1hr TTL)  | URL, project, username, label          |
| `.jira/current-ticket.cache` | Current ticket details | Beads ID, JIRA key, URL, title, status |
| `.beads/current-issue`       | Beads issue ID         | Just the ID (e.g., `bd-100`)           |

**Security:** `JIRA_API_TOKEN` is NEVER stored in cache files. It must always come from the environment variable.

**Cache structure:**

```
.jira/
├── config.cache           # JIRA URL, project, username (no secrets)
└── current-ticket.cache   # Current ticket details for fast hook access

.beads/
├── current-issue          # Contains beads issue ID (e.g., "bd-100")
├── issues/                # Beads issue storage
│   ├── bd-100.md
│   ├── bd-101.md
│   └── ...
└── config.json            # JIRA configuration
```

## Beads Issue Tracking

The `.beads/current-issue` file contains the beads issue ID (e.g., `bd-100`). The beads issue has:

- `id`: Beads issue ID (e.g., `bd-100`)
- `title`: Issue title/summary
- `external_ref`: JIRA URL (e.g., `https://badal.atlassian.net/browse/PGF-123`)
- `status`: Issue status (open, in_progress, blocked, deferred, closed)

## Integration with agent-fork-join

When `.beads/current-issue` exists, agent-fork-join will:

1. **Commits**: Prepend JIRA ticket ID to commit messages
   - Extracts JIRA key from beads issue's `external_ref`
   - Format: `PGF-123: feat: add login form`
   - Enables JIRA Smart Commits

2. **PRs**: Include ticket in PR title and description
   - Title: `PGF-123: Implement login feature`
   - Description includes link to JIRA ticket

3. **PR Comments**: Comment on beads issue (syncs to JIRA)
   - On PR creation: Summary + PR link
   - On PR merge: "PR merged" notification

4. **/done Command**: Ask about issue status
   - Offer to transition issue (Done, In Review, etc.)
   - Status changes sync to JIRA via beads
   - Clean up `.beads/current-issue` only if user selects "Done"

## Prerequisite Instructions

### If JIRA_API_TOKEN is not set

```
JIRA API token is required but not set.

To get your API token:
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Label it (e.g., "beads-sync")
4. Copy the token

Then set it in your environment:
  export JIRA_API_TOKEN="your_token_here"

For persistence, add this to your shell profile (~/.bashrc, ~/.zshrc, etc.)
```

### If beads CLI is not installed

```
beads CLI is required but not installed.

Install beads:
  go install github.com/beads-dev/beads/cmd/bd@latest

Or download from: https://github.com/beads-dev/beads/releases

After installation, run /jira:setup again.
```

## Workflow Diagram

```
User: /jira:setup
    │
    ▼
┌─────────────────────────────────────────┐
│ Configure JIRA + beads integration      │
│ Creates .jira/config.cache              │
└─────────────────────────────────────────┘
    │
    ▼
User: /jira:work PGF-123   (or just /jira:work to list)
    │
    ▼
┌─────────────────────────────────────────┐
│ Load config from cache (fast)           │
│ Sync tickets from JIRA via beads        │
│ Map JIRA key → beads issue ID           │
│ Create .beads/current-issue             │
│ Create .jira/current-ticket.cache       │
└─────────────────────────────────────────┘
    │
    ▼
User submits first prompt...
    │
    ▼
┌─────────────────────────────────────────┐
│ Hook reads cache (no bd calls)          │
│ Auto-set status to "In Progress"        │
│ Sync status change to JIRA              │
│ Update cache                            │
└─────────────────────────────────────────┘
    │
    ▼
agent-fork-join hooks detect .beads/current-issue
    │
    ├── Read JIRA key from cache (fast)
    ├── Commit: "PGF-123: feat: add feature"
    │
    ├── PR created → Comment on beads issue (syncs to JIRA)
    │
    ▼
User: /done
    │
    ▼
┌─────────────────────────────────────────┐
│ Ask about issue status change           │
│ PR merged → Comment on beads issue      │
│ Status changes sync to JIRA             │
│ Clean up caches (if Done)               │
└─────────────────────────────────────────┘
```

## JIRA Interactions via beads

All JIRA interactions use the beads CLI:

```bash
# Sync issues
bd jira sync --pull
bd jira sync --push

# Comment on issue (via beads)
bd comments add <issue-id> --body "PR created: <url>"

# Update issue status (if supported)
bd update <issue-id> --status=done
```
