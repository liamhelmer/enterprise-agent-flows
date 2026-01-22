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

Use `/jira:work` to start working on a JIRA ticket.

The command will:

1. **Check Prerequisites**
   - Verify JIRA is configured (run `/jira:setup` if not)

2. **Sync with JIRA**
   - Pull latest tickets from JIRA via beads

3. **Present Ticket Selection**
   - List open tickets, prioritizing those assigned to the user
   - Attempt to guess the best match if context is provided
   - Allow user to select or enter ticket ID manually

4. **Map JIRA to Beads Issue**
   - Find the beads issue ID from the selected JIRA ticket key
   - The beads issue contains the JIRA URL in its `external_ref` field

5. **Set Up Tracking**
   - Write the beads issue ID to `.beads/current-issue`
   - agent-fork-join will detect this file for smart commits

## Beads Issue Tracking

The `.beads/current-issue` file contains the beads issue ID (e.g., `bd-100`). The beads issue has:

- `id`: Beads issue ID (e.g., `bd-100`)
- `title`: Issue title/summary
- `external_ref`: JIRA URL (e.g., `https://badal.atlassian.net/browse/PGF-123`)
- `status`: Issue status (open, in_progress, blocked, deferred, closed)

```
.beads/
├── current-issue     # Contains beads issue ID (e.g., "bd-100")
├── issues/           # Beads issue storage
│   ├── bd-100.md
│   ├── bd-101.md
│   └── ...
└── config.json       # JIRA configuration
```

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
└─────────────────────────────────────────┘
    │
    ▼
User: /jira:work
    │
    ▼
┌─────────────────────────────────────────┐
│ Sync tickets from JIRA via beads        │
│ Present ticket selection (JIRA keys)    │
│ Map JIRA key → beads issue ID           │
│ Create .beads/current-issue             │
└─────────────────────────────────────────┘
    │
    ▼
User works on code...
    │
    ▼
agent-fork-join hooks detect .beads/current-issue
    │
    ├── Extract JIRA key from beads issue
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
│ Clean up .beads/current-issue (if Done) │
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
