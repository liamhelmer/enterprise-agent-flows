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
   - JIRA username: Default to git email (allow override)

4. **Setup beads**
   - Initialize beads if `.beads/` directory doesn't exist
   - Run `bd doctor --fix` to resolve any issues

5. **Configure JIRA**
   - Set `jira.url` config
   - Set `jira.project` config
   - Set `jira.label` config (if provided)
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

4. **Set Up Tracking**
   - Create `.jira/` directory
   - Create ticket file at `.jira/TICKET-ID`
   - Create symlink `.jira/current-ticket` → ticket file

5. **Enable Smart Commits**
   - agent-fork-join will detect `.jira/current-ticket`
   - All commits will include ticket ID
   - PRs will reference the ticket

## .jira Directory Structure

```
.jira/
├── current-ticket -> PGF-123     # Symlink to active ticket
├── PGF-123                        # Ticket metadata file
│   ticket_id=PGF-123
│   started_at=2024-01-15T10:30:00Z
│   summary=Implement login feature
│   url=https://badal.atlassian.net/browse/PGF-123
└── PGF-456                        # Previous ticket (if any)
```

## Integration with agent-fork-join

When `.jira/current-ticket` exists, agent-fork-join will:

1. **Commits**: Prepend ticket ID to commit messages
   - Format: `PGF-123: feat: add login form`
   - Enables JIRA Smart Commits

2. **PRs**: Include ticket in PR title and description
   - Title: `PGF-123: Implement login feature`
   - Description includes link to JIRA ticket

3. **PR Comments**: Comment on JIRA ticket
   - On PR creation: Summary + PR link
   - On PR merge: "PR merged" notification

4. **/done Command**: Ask about ticket status
   - Offer to transition ticket (Done, In Review, etc.)
   - Clean up `.jira/current-ticket` only if user selects "Done"

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
│ Sync tickets from JIRA                  │
│ Present ticket selection                │
│ Create .jira/current-ticket             │
└─────────────────────────────────────────┘
    │
    ▼
User works on code...
    │
    ▼
agent-fork-join hooks detect .jira/current-ticket
    │
    ├── Commit: "PGF-123: feat: add feature"
    │
    ├── PR created → Comment on JIRA ticket
    │
    ▼
User: /done
    │
    ▼
┌─────────────────────────────────────────┐
│ Ask about JIRA ticket status change     │
│ PR merged → Comment "PR merged" on JIRA │
│ Clean up .jira/current-ticket (if Done) │
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
