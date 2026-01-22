---
name: "setup"
description: "Set up JIRA integration with beads for bidirectional issue synchronization."
---

# /jira:setup Command

Configure JIRA Cloud integration with beads issue tracking. This command validates prerequisites, guides you through configuration, and performs initial synchronization.

## When This Command Is Invoked

Execute the following steps in order:

### Step 1: Check Prerequisites

Check for required prerequisites before proceeding:

```bash
# Check for JIRA_API_TOKEN
if [[ -z "$JIRA_API_TOKEN" ]]; then
    echo "JIRA_API_TOKEN not set"
    # Exit and show instructions
fi

# Check for beads CLI
if ! command -v bd &> /dev/null; then
    echo "beads CLI not installed"
    # Exit and show instructions
fi
```

**If JIRA_API_TOKEN is not set**, tell the user:

```
Missing: JIRA_API_TOKEN environment variable

To get your API token:
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Label it (e.g., "beads-sync")
4. Copy the token

Then set it in your environment:
  export JIRA_API_TOKEN="your_token_here"

For persistence, add to your shell profile (~/.bashrc, ~/.zshrc, etc.)

After setting the token, run /jira:setup again.
```

**If beads CLI is not installed**, tell the user:

```
Missing: beads CLI (bd command)

Install beads:
  go install github.com/beads-dev/beads/cmd/bd@latest

Or download from: https://github.com/beads-dev/beads/releases

After installation, run /jira:setup again.
```

**IMPORTANT**: If any prerequisite is missing, STOP here and do not proceed to the next steps.

### Step 2: Get Defaults

Before prompting the user, retrieve sensible defaults:

```bash
# Get email from git global config for JIRA username default
git_email=$(git config --global user.email 2>/dev/null || echo "")

# Default JIRA URL
default_jira_url="https://badal.atlassian.net"
```

### Step 3: Collect Configuration

If prerequisites are met, use the AskUserQuestion tool to collect configuration.
Present defaults and allow user to override:

1. **JIRA URL** (required, default: https://badal.atlassian.net)
   - Header: "JIRA URL"
   - Question: "What is your JIRA Cloud URL?"
   - Options:
     - "https://badal.atlassian.net (Recommended)" - Use default Badal instance
     - "Other" - Specify a different JIRA instance
   - If user selects "Other", ask for the custom URL

2. **Project Key** (required)
   - Header: "Project"
   - Question: "What is your JIRA project key?"
   - Note: This is the prefix in issue IDs (e.g., PROJ in PROJ-123)

3. **Label Filter** (optional)
   - Header: "Label"
   - Question: "Would you like to filter by a JIRA label? (optional)"
   - Options:
     - "No label filter" - Sync all issues in project
     - "Specify a label" - Only sync issues with this label

4. **JQL Filter** (optional, recommended default)
   - Header: "JQL Filter"
   - Question: "Would you like to add a JQL filter to limit which issues are synced?"
   - Options:
     - "Active issues only (Recommended)" - Use default: `sprint in openSprints() OR status in ("In Review", "In Progress")`
     - "No JQL filter" - Sync all issues matching project/label
     - "Custom JQL" - Specify a custom JQL expression
   - Default JQL: `sprint in openSprints() OR status in ("In Review", "In Progress")`
   - This limits sync to issues that are actively being worked on

5. **JIRA Username** (required, default from git config)
   - Header: "Username"
   - Question: "What is your JIRA email/username?"
   - If git email is available, show: "Use [git_email] (from git config)?" with options:
     - "[git_email] (Recommended)" - Use the git config email
     - "Other" - Specify a different email
   - If no git email found, ask for the email directly

### Step 4: Initialize beads

Check if beads is initialized in the repository:

```bash
# Check if .beads directory exists
if [[ ! -d ".beads" ]]; then
    echo "Initializing beads..."
    bd init
fi
```

### Step 5: Run beads Doctor

Fix any beads configuration issues:

```bash
bd doctor --fix
```

### Step 6: Configure JIRA Integration

Set the JIRA configuration values:

```bash
# Set JIRA URL
bd config set jira.url "$JIRA_URL"

# Set project key
bd config set jira.project "$PROJECT_KEY"

# Set label (if provided)
if [[ -n "$LABEL" ]]; then
    bd config set jira.label "$LABEL"
fi

# Set JQL filter (if provided)
if [[ -n "$JQL_FILTER" ]]; then
    bd config set jira.jql "$JQL_FILTER"
fi

# Set username
bd config set jira.username "$USERNAME"
```

### Step 7: Verify Configuration

Show the configured values:

```bash
bd config list | grep jira
```

### Step 8: Initial Sync

Perform the first sync from JIRA:

```bash
bd jira sync --pull
```

### Step 9: Show Summary

Display a summary of what was configured and useful next commands:

```
=== Setup Complete ===

Your beads instance is now connected to JIRA.

Configuration:
  URL:      https://company.atlassian.net
  Project:  PROJ
  Label:    DevEx
  JQL:      sprint in openSprints() OR status in ("In Review", "In Progress")
  Username: user@company.com

Useful commands:
  bd jira sync --pull   # Pull issues from JIRA
  bd jira sync --push   # Push issues to JIRA
  bd jira sync          # Bidirectional sync
  bd jira status        # Check sync status
  bd list               # List local issues
```

## Error Handling

### Sync fails with authentication error

```
Sync failed: Authentication error

Please verify:
1. JIRA_API_TOKEN is set correctly
2. jira.username matches your Atlassian account email
3. You have access to the specified project

Run: bd jira status
```

### Project not found

```
Sync failed: Project not found

Please verify:
1. The project key is correct (e.g., "PROJ" not "Project Name")
2. You have access to this project in JIRA

Check your JIRA projects at: https://company.atlassian.net/jira/projects
```
