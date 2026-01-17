# Agent Fork-Join E2E Tests

End-to-end test suite for the `agent-fork-join` plugin.

## CRITICAL Test Requirements

The following requirements are **MANDATORY** for the E2E test to be valid:

1. **NO `--dangerously-skip-permissions`**: The test must NOT use the `--dangerously-skip-permissions` flag.
   Instead, it uses `--allowedTools` with specific scoped permissions for security.

2. **Prompt must NOT specify git operations**: The test prompt must NOT mention:
   - Creating branches (feature branch, agent branches)
   - Making commits
   - Creating pull requests
   - Pushing to remote

3. **Plugin must handle ALL git operations**: For the test to pass, the plugin's hooks MUST automatically:
   - Create the feature branch via `UserPromptSubmit` hook
   - Create commits via `AgentComplete` hook
   - Create the pull request when all work is complete

4. **Plugin installation via `claude plugin` command**: The test must NOT manually copy plugin files.
   Instead, it MUST use the Claude CLI plugin commands to simulate marketplace installation:

   ```bash
   # Add the plugins directory as a local marketplace
   claude plugin marketplace add /path/to/plugins

   # Install the plugin from that marketplace
   claude plugin install agent-fork-join --scope project
   ```

   This ensures the plugin is installed the same way users would install from the marketplace.

If any git operation needs to be specified in the test prompt, that indicates the plugin is NOT
working correctly and the test should fail.

## Overview

This test suite validates the complete workflow of the agent-fork-join plugin by:

1. Creating a unique test repository on GitHub
2. Initializing it with proper configuration files
3. Running Claude with a prompt that spawns 5 concurrent agents
4. Verifying the expected git branches, commits, and PR are created
5. Optionally cleaning up the test repository

## Prerequisites

- **gh CLI**: Authenticated with GitHub (`gh auth login`)
- **claude CLI**: Installed and configured
- **cargo**: For building the Rust daemon
- **jq**: For JSON parsing
- **git**: For repository operations

## Non-Interactive Mode

The test runs Claude in fully non-interactive mode using scoped permissions:

**File operations** (scoped to test directory):

- `Read(${TEST_DIR}/**)` - Read files in test repo only
- `Write(${TEST_DIR}/**)` - Create files in test repo only
- `Edit(${TEST_DIR}/**)` - Edit files in test repo only
- `Glob`, `Grep`, `LS` - Search within test repo

**Bash commands** (specific patterns):

- `Bash(git *)` - Git operations
- `Bash(gh pr *)`, `Bash(gh repo *)` - GitHub CLI
- `Bash(npm test)`, `Bash(npm run *)` - Validation
- `Bash(mkdir *)`, `Bash(ls *)` - Directory operations

**Agent spawning**:

- `Task` - For spawning concurrent agents

This approach allows the test to run without user intervention while maintaining security by only allowing the specific operations needed for the test.

## Quick Start

```bash
# Run the E2E test (keeps repository for inspection)
./e2e-test.sh

# Run with automatic cleanup
./e2e-test.sh --clean

# Run with verbose output
./e2e-test.sh --verbose

# Run in a different GitHub org/user
./e2e-test.sh --org your-username
```

## Test Script Options

### e2e-test.sh

```
Usage: ./e2e-test.sh [OPTIONS]

Options:
  --clean           Clean up the test repository after test completes
  --org ORG         GitHub organization/user (default: liamhelmer)
  --timeout SECS    Timeout in seconds (default: 300, test fails if exceeded)
  --model MODEL     Claude model to use (default: haiku)
  --repo NAME       Use specific repo name instead of generated one
  --verbose, -v     Verbose output
  --help, -h        Show help message
```

### cleanup.sh

```
Usage: ./cleanup.sh [OPTIONS] [REPO_NAME]

Options:
  --all              Delete all test repositories (fork-join-test-*)
  --list             List test repositories without deleting
  --dry-run          Show what would be deleted
  --org ORG          GitHub organization/user (default: liamhelmer)
  --help, -h         Show help message
```

## What the Test Validates

| Check          | Description                                                    |
| -------------- | -------------------------------------------------------------- |
| Feature Branch | A `feature/` branch was created                                |
| Commits        | At least 5 commits exist (one per agent)                       |
| Pull Request   | A PR was created to merge the feature branch                   |
| Directories    | All 5 module directories exist (`src/auth/`, `src/api/`, etc.) |

## Test Repository Structure

The test creates a repository with:

```
test-repo/
├── CLAUDE.md           # Project instructions
├── AGENTS.md           # Agent definitions (5 agents)
├── package.json        # For validation scripts
└── .claude/
    ├── settings.json   # Hook configuration
    └── plugins/
        └── agent-fork-join/
            ├── plugin.json
            ├── SKILL.md
            ├── hooks/
            │   ├── on-prompt-submit.sh
            │   ├── on-agent-spawn.sh
            │   └── on-agent-complete.sh
            ├── scripts/
            └── daemon/
                └── target/release/merge-daemon
```

## Expected Workflow

When the test runs:

1. **Prompt Submitted**: Hook detects code-changing prompt, creates feature branch
2. **Agents Spawn**: Each of 5 agents gets its own git worktree
3. **Agents Work**: Each agent creates files in their assigned directory
4. **Agents Complete**: Changes are committed to agent branches
5. **Merge Queue**: Daemon merges all agent branches into feature branch
6. **PR Created**: Draft PR is created with aggregated commit messages
7. **Validation**: Tests/lint run on the merged code
8. **Ready**: PR is marked ready for review

## Logs

Test logs are saved to:

```
tests/agent-fork-join/logs/fork-join-test-TIMESTAMP-claude.log
```

## Troubleshooting

### Test times out

- Increase timeout: `./e2e-test.sh --timeout 900`
- Check Claude is responding: `claude --version`

### Repository already exists

- Use a different name: `./e2e-test.sh --repo my-unique-name`
- Clean up old repos: `./cleanup.sh --list` then `./cleanup.sh REPO_NAME`

### Missing prerequisites

The test will check for required tools and report any missing ones.

### Build failures

If the Rust daemon isn't built:

```bash
cd ../../plugins/agent-fork-join/daemon
cargo build --release
```

## Cleaning Up

After testing, clean up repositories:

```bash
# List all test repos
./cleanup.sh --list

# Delete all test repos (with confirmation)
./cleanup.sh --all

# Preview what would be deleted
./cleanup.sh --dry-run --all

# Delete specific repo
./cleanup.sh fork-join-test-20240115-123456
```
