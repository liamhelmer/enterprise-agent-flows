# Git Helper

Git workflow assistant that helps with commits, branches, and repository management.

## Usage

```
/git-helper [command] [options]
```

## Commands

### commit

Create well-formatted commit messages based on your changes.

```
/git-helper commit
```

Options:

- `--conventional`: Use conventional commits format
- `--emoji`: Add appropriate emoji prefixes
- `--scope <scope>`: Specify commit scope

### branch

Manage branches with smart naming conventions.

```
/git-helper branch create feature/new-feature
/git-helper branch cleanup
```

### pr

Help create and manage pull requests.

```
/git-helper pr create
/git-helper pr describe
```

### log

Analyze git history and provide insights.

```
/git-helper log summary
/git-helper log contributors
```

## Examples

### Create a Commit

```
/git-helper commit --conventional

# Analyzes staged changes and suggests:
# feat(auth): add OAuth2 login support
#
# - Add Google OAuth provider
# - Add GitHub OAuth provider
# - Update login page with social buttons
```

### Create a Feature Branch

```
/git-helper branch create --from main

# Suggests branch name based on context:
# feature/add-user-authentication
```

### Generate PR Description

```
/git-helper pr create

# Generates PR with:
# - Title based on commits
# - Summary of changes
# - Testing checklist
# - Screenshots placeholder
```

## Configuration

Set defaults in your project's `.claude/config.json`:

```json
{
  "git-helper": {
    "commitFormat": "conventional",
    "branchPrefix": "feature/",
    "prTemplate": "default"
  }
}
```

## Notes

- Requires git to be installed and initialized in the current directory
- Works best with staged changes for commit analysis
- Respects existing .gitmessage templates
