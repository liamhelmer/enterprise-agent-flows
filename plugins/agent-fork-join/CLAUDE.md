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
3. Pushes changes to remote
4. Creates a PR with:
   - AI-generated summary
   - Complete original prompt in metadata

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

## Multi-Agent Workflow (Future)

The daemon infrastructure supports:

1. Each spawned agent gets its own worktree
2. Agent changes are committed to separate branches
3. FIFO merge queue handles sequential integration
4. Conflict resolution and rebasing when needed
5. Final PR created when all agents complete
