---
name: "JIRA"
description: "Complete JIRA integration for development workflows with ticket tracking, smart commits, PR automation, and bidirectional sync via beads."
---

# JIRA Plugin

A comprehensive plugin for integrating JIRA into your development workflow. Enables smart commits, automatic PR linking, and seamless ticket tracking.

## Overview

This plugin provides:

- **Setup Wizard**: Configure JIRA integration with beads
- **Ticket Tracking**: Start working on specific JIRA tickets with `/jira:work`
- **Smart Commits**: Automatic JIRA ticket linking in commit messages
- **PR Automation**: JIRA tickets linked in PRs with automatic comments
- **Status Management**: Update ticket status via `/done` command

## Commands

### /jira:setup - Configure JIRA Integration

Initial setup to connect your repository to JIRA via beads.

```
/jira:setup
```

**What it does:**

1. Checks for `JIRA_API_TOKEN` environment variable
2. Checks for beads CLI installation
3. Prompts for configuration (with smart defaults):
   - JIRA URL (default: https://badal.atlassian.net)
   - Project key (e.g., PGF)
   - Optional label filter
   - Username (default: from git config)
4. Initializes beads if not present
5. Configures JIRA integration
6. Performs initial sync

### /jira:work - Start Working on a Ticket

Select a JIRA ticket to work on. Enables smart commits and PR linking.

```
/jira:work
```

**What it does:**

1. Syncs tickets from JIRA
2. Presents a list of open tickets (your assigned tickets first)
3. Attempts to guess the best match based on context
4. Creates `.jira/current-ticket` tracking file

**After running /jira:work:**

- All commits will include the JIRA ticket ID
- PRs will link to the JIRA ticket
- JIRA will be commented when PRs are created/merged

## Integration with agent-fork-join

When a JIRA ticket is being tracked (`.jira/current-ticket` exists):

### Commits

- Format: `PGF-123: feat(scope): description`
- Enables JIRA Smart Commits for automatic linking

### Pull Requests

- Ticket ID included in PR title
- JIRA ticket link in PR description
- Automatic comment on JIRA ticket with PR summary

### /done Command

- Comments "PR merged" on JIRA ticket
- Asks if ticket status should be updated (Done, In Review, etc.)
- Cleans up `.jira/current-ticket` symlink **only if status is set to Done**

## .jira Directory Structure

```
.jira/
├── current-ticket -> PGF-123     # Symlink to active ticket
└── PGF-123                        # Ticket metadata file
    ticket_id=PGF-123
    started_at=2024-01-15T10:30:00Z
    summary=Implement login feature
    url=https://badal.atlassian.net/browse/PGF-123
```

Note: The `.jira/` directory is tracked in git (not excluded via `.gitignore`).

## Prerequisites

### 1. JIRA API Token

Get your token from Atlassian:

1. Go to [Atlassian API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click "Create API token"
3. Give it a label (e.g., "beads-sync")
4. Copy the generated token

Set the token:

```bash
export JIRA_API_TOKEN="your_api_token_here"
```

For persistence, add to your shell profile (~/.bashrc, ~/.zshrc, etc.).

### 2. Beads CLI

Install beads:

```bash
go install github.com/beads-dev/beads/cmd/bd@latest
```

Or download from [releases](https://github.com/beads-dev/beads/releases).

## Configuration

After setup, these beads config values are set:

| Key             | Description             | Example                     |
| --------------- | ----------------------- | --------------------------- |
| `jira.url`      | JIRA Cloud instance URL | https://badal.atlassian.net |
| `jira.project`  | JIRA project key        | PGF                         |
| `jira.label`    | Optional label filter   | DevEx                       |
| `jira.username` | Your JIRA email         | user@badal.com              |

## Workflow Example

```bash
# 1. Initial setup (one time)
/jira:setup

# 2. Start working on a ticket
/jira:work
# → Select PGF-123 from the list

# 3. Do your work...
# → Commits will include "PGF-123: ..."
# → PR will link to JIRA ticket
# → JIRA ticket will get PR comment

# 4. After PR is merged
/done
# → Comments "PR merged" on JIRA
# → Asks about updating ticket status
# → Cleans up local state
```

## Sync Commands

Manual sync with JIRA:

```bash
# Pull issues from JIRA
bd jira sync --pull

# Push local issues to JIRA
bd jira sync --push

# Bidirectional sync
bd jira sync

# Preview without changes
bd jira sync --dry-run

# Check sync status
bd jira status
```

## Troubleshooting

### JIRA_API_TOKEN not set

```bash
export JIRA_API_TOKEN="your_token"
```

### beads not found

```bash
go install github.com/beads-dev/beads/cmd/bd@latest
```

### Authentication failed

1. Verify your API token is correct
2. Ensure `jira.username` matches your Atlassian email
3. Check that you have access to the specified project

### Sync issues

```bash
bd doctor --fix
bd jira status
```
