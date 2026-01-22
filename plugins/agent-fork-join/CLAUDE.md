# Agent Fork Join

## Activation Conditions

The plugin activates automatically when:

1. The repository has a **GitHub remote** (origin URL contains github.com)
2. You are on the **default branch** (main/master) OR on a **plugin-created branch** (Angular-style: feat/, fix/, etc.)

The plugin will NOT activate for:

- Non-GitHub repositories
- User's own feature branches that don't follow the Angular convention

## Hook Workflow

### UserPromptSubmit (on new prompt)

1. Checks if prompt will make code changes (keywords: implement, add, create, fix, etc.)
2. If on default branch AND changes expected:
   - Creates an Angular-style feature branch (feat/, fix/, refactor/, etc.)
   - AI generates branch name based on prompt content
   - Immediately pushes branch to origin

### PostToolUse (on file writes)

1. Detects Write/Edit/MultiEdit tool completions
2. **Tracks files** for later commit (does NOT commit immediately)
3. This ensures a single commit per session, not per-file

### Stop (session end)

1. Commits ALL tracked changes in a **single commit**
2. Uses AI to generate Angular-style commit message
3. **If JIRA ticket is tracked** (`.jira/current-ticket` exists):
   - Prepends ticket ID to commit message (e.g., `PGF-123: feat: add feature`)
   - Enables JIRA Smart Commits
4. Pushes changes to remote
5. Creates a PR with:
   - AI-generated summary
   - Complete original prompt in metadata
   - **JIRA ticket link** (if tracked)
6. **Comments on JIRA ticket** with PR summary and link (if tracked)

## Angular Commit Types

| Type       | Description                                                   |
| ---------- | ------------------------------------------------------------- |
| `build`    | Changes that affect the build system or external dependencies |
| `ci`       | Changes to CI configuration files and scripts                 |
| `docs`     | Documentation only changes                                    |
| `feat`     | A new feature                                                 |
| `fix`      | A bug fix                                                     |
| `perf`     | A code change that improves performance                       |
| `refactor` | A code change that neither fixes a bug nor adds a feature     |
| `test`     | Adding missing tests or correcting existing tests             |

## Commands

### /done - Complete Branch Workflow (Local Only)

Use `/done` when your PR has been merged and you want to clean up locally:

1. **Check PR status** (was it merged?)
2. **Comment on JIRA** - "PR merged" (if JIRA ticket tracked)
3. **Ask about JIRA status** - Use AskUserQuestion to ask if ticket status should change:
   - Options: "Done", "In Review", "No change"
   - Update status via beads if requested
4. **Switch to main branch**
5. **Pull latest changes**
6. **Delete local feature branch** (if PR was merged)
7. **Clean up JIRA tracking** - Remove `.jira/current-ticket` symlink (only if user selects "Done")
8. **Run /compact** to consolidate conversation history

```
/done
```

**Note:** This command does NOT merge PRs remotely. Merge your PR on GitHub first, then run `/done` to clean up your local environment.

## JIRA Integration

When `.jira/current-ticket` exists (set by `/jira:work`), this plugin automatically:

### On Commit

- Prepends JIRA ticket ID to commit message
- Format: `PGF-123: feat(scope): description`
- Enables JIRA Smart Commits for automatic linking

### On PR Creation

- Includes JIRA ticket in PR title
- Adds JIRA ticket link in PR description
- Comments on JIRA ticket with PR summary and link

### On /done (when PR merged)

- Comments "PR merged" on JIRA ticket
- Asks user about updating ticket status (Done, In Review, etc.)
- Cleans up `.jira/current-ticket` symlink only if user selects "Done"

## PR Prompt History

Each PR description includes a "Prompt History" section with timestamped collapsible accordions for each prompt submitted during the session. When continuing work on an existing PR branch, new prompts are automatically appended to this history.

## Multi-Agent Workflow (Future)

The daemon infrastructure supports:

1. Each spawned agent gets its own worktree
2. Agent changes are committed to separate branches
3. FIFO merge queue handles sequential integration
4. Conflict resolution and rebasing when needed
5. Final PR created when all agents complete
