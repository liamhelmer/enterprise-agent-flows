#!/usr/bin/env bash
# Stop Hook - Commits changes and creates PR when session completes
#
# This hook:
# 1. Checks if we're on a feature branch
# 2. Uses AI to generate an Angular-style commit message
# 3. Commits any uncommitted changes
# 4. Pushes to remote
# 5. Creates a PR if one doesn't exist

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/fork-join-hook-debug.log"
debug_log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STOP] $*" >>"${DEBUG_LOG}"
	echo "[HOOK DEBUG] [STOP] $*" >&2
}

debug_log "=== Stop hook started ==="
debug_log "PWD: $(pwd)"

# Guard against recursive hook calls
if [[ "${FORK_JOIN_HOOK_CONTEXT:-}" == "1" ]]; then
	debug_log "Already in hook context, skipping to prevent recursion"
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
debug_log "SCRIPT_DIR: ${SCRIPT_DIR}"

# Source dependencies
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
	source "${SCRIPT_DIR}/lib/common.sh"
	debug_log "Sourced common.sh"
else
	debug_log "ERROR: common.sh not found"
	exit 0 # Don't fail the session
fi

if [[ -f "${SCRIPT_DIR}/lib/git-utils.sh" ]]; then
	source "${SCRIPT_DIR}/lib/git-utils.sh"
	debug_log "Sourced git-utils.sh"
else
	debug_log "ERROR: git-utils.sh not found"
	exit 0
fi

# Valid Angular commit types
VALID_TYPES=("build" "ci" "docs" "feat" "fix" "perf" "refactor" "test")

# Get current beads issue if available
CURRENT_BEADS_ISSUE=""
CURRENT_JIRA_TICKET=""
JIRA_TICKET_URL=""
if current_issue=$(beads_get_current_issue 2>/dev/null); then
	CURRENT_BEADS_ISSUE="$current_issue"
	CURRENT_JIRA_TICKET=$(beads_get_jira_key "$current_issue" 2>/dev/null || echo "")
	JIRA_TICKET_URL=$(beads_get_jira_url "$current_issue" 2>/dev/null || echo "")
	debug_log "Beads issue detected: $CURRENT_BEADS_ISSUE (JIRA: $CURRENT_JIRA_TICKET)"
fi

# Generate a plain English summary of the task and work done using AI
generate_ai_pr_summary() {
	local original_prompt="$1"
	local commit_log="$2"
	local branch_name="$3"

	debug_log "Using Claude AI to generate PR summary..."

	# Sanitize inputs for AI (truncate if too long)
	local sanitized_prompt
	sanitized_prompt=$(echo "$original_prompt" | tr '\n' ' ' | head -c 1000)
	local sanitized_commits
	sanitized_commits=$(echo "$commit_log" | head -c 1500)

	local ai_prompt="Generate a PR description for the following work.

ORIGINAL TASK:
${sanitized_prompt}

COMMITS MADE:
${sanitized_commits}

BRANCH: ${branch_name}

Generate a PR description with these sections:
1. **Summary**: 2-3 sentences describing what was requested in plain English
2. **Changes Made**: Bullet list of what was implemented, based on the commits
3. **Why**: Brief explanation of why these changes were made

Keep it concise and professional. Output only the PR description, no extra commentary."

	export FORK_JOIN_HOOK_CONTEXT=1
	local summary=""
	summary=$(claude_fast_call "$ai_prompt" 15)
	unset FORK_JOIN_HOOK_CONTEXT

	if [[ -n "$summary" ]]; then
		debug_log "AI generated PR summary successfully"
		echo "$summary"
		return 0
	else
		debug_log "AI PR summary was empty"
		return 1
	fi
}

# Generate a fallback PR summary without AI
generate_fallback_pr_summary() {
	local original_prompt="$1"
	local commit_log="$2"
	local commit_type="$3"

	# Extract first sentence or line from prompt as summary
	local first_line
	first_line=$(echo "$original_prompt" | head -1 | sed 's/[[:space:]]*$//')
	if [[ ${#first_line} -gt 200 ]]; then
		first_line="${first_line:0:197}..."
	fi

	# Build changes section from commits
	local changes_section=""
	if [[ -n "$commit_log" ]]; then
		changes_section="## Changes Made

$(echo "$commit_log" | sed 's/^/- /')"
	fi

	cat <<EOF
## Summary

${first_line}

${changes_section}

## Why

This PR implements the requested changes as a ${commit_type} task.
EOF
}

# Extract commit type from branch name
get_commit_type_from_branch() {
	local branch_name="$1"
	for type in "${VALID_TYPES[@]}"; do
		if [[ "$branch_name" == "${type}/"* ]]; then
			echo "$type"
			return 0
		fi
	done
	echo "feat" # Default
}

# Use AI to generate an Angular-style commit message
generate_ai_commit_message() {
	local changes="$1"
	local session_prompt="$2"
	local branch_name="$3"

	debug_log "Using Claude AI to generate commit message..."

	# Get the commit type from branch name
	local commit_type
	commit_type="$(get_commit_type_from_branch "$branch_name")"

	local ai_prompt
	ai_prompt="$(
		cat <<AIPROMPT
Generate an Angular-style commit message for the following changes.

COMMIT MESSAGE FORMAT:
<type>(<scope>): <short summary>

<body>

RULES:
1. type: Must be "$commit_type" (derived from branch name)
2. scope: Optional, area of code affected (e.g., auth, api, db)
3. summary: Imperative mood, lowercase, no period, max 72 chars
4. body: Explain WHY the change was made, not just what

BRANCH NAME: $branch_name

ORIGINAL TASK:
$session_prompt

FILES CHANGED:
$changes

Generate ONLY the commit message, nothing else.
AIPROMPT
	)"

	# Call Claude CLI with FORK_JOIN_HOOK_CONTEXT to prevent recursive hooks
	export FORK_JOIN_HOOK_CONTEXT=1
	local commit_msg
	commit_msg=$(claude_fast_call "$ai_prompt" 10)
	unset FORK_JOIN_HOOK_CONTEXT

	if [[ -n "$commit_msg" ]]; then
		# Validate it starts with a valid type
		local first_word
		first_word=$(echo "$commit_msg" | head -1 | cut -d'(' -f1 | cut -d':' -f1)
		local valid=false
		for type in "${VALID_TYPES[@]}"; do
			if [[ "$first_word" == "$type" ]]; then
				valid=true
				break
			fi
		done

		if [[ "$valid" == "true" ]]; then
			debug_log "AI generated valid commit message"
			echo "$commit_msg"
			return 0
		else
			debug_log "AI commit message has invalid type: $first_word"
			return 1
		fi
	else
		debug_log "AI returned empty commit message"
		return 1
	fi
}

# Generate a heuristic commit message following Angular style
generate_heuristic_commit_message() {
	local changes="$1"
	local session_prompt="$2"
	local branch_name="$3"

	# Get commit type from branch name
	local commit_type
	commit_type="$(get_commit_type_from_branch "$branch_name")"

	# Try to determine scope from changed files
	local scope=""
	local first_dir
	first_dir=$(echo "$changes" | head -1 | cut -d'/' -f1)
	if [[ "$first_dir" == "src" ]]; then
		scope=$(echo "$changes" | head -1 | cut -d'/' -f2)
	elif [[ -n "$first_dir" && "$first_dir" != "." ]]; then
		scope="$first_dir"
	fi

	# Extract description from branch name
	local description
	description=$(echo "$branch_name" | sed 's/^[^/]*\///' | tr '-' ' ')

	# Build the commit message
	local header
	if [[ -n "$scope" ]]; then
		header="${commit_type}(${scope}): ${description}"
	else
		header="${commit_type}: ${description}"
	fi

	# Truncate header if too long
	if [[ ${#header} -gt 72 ]]; then
		header="${header:0:69}..."
	fi

	# Build body from session prompt
	local body=""
	if [[ -n "$session_prompt" ]]; then
		body="Session work based on:
${session_prompt:0:200}"
	fi

	# Combine header and body
	if [[ -n "$body" ]]; then
		echo "${header}

${body}"
	else
		echo "$header"
	fi
}

# Generate commit message (tries AI first, falls back to heuristic)
# If JIRA ticket is set, prepends ticket ID for smart commits
generate_commit_message() {
	local changes="$1"
	local session_prompt="$2"
	local branch_name="$3"

	local commit_msg=""

	# Try AI first
	if commit_msg="$(generate_ai_commit_message "$changes" "$session_prompt" "$branch_name")"; then
		:
	else
		# Fall back to heuristic
		debug_log "Falling back to heuristic commit message generation"
		commit_msg=$(generate_heuristic_commit_message "$changes" "$session_prompt" "$branch_name")
	fi

	# Prepend JIRA ticket ID for smart commits if available
	if [[ -n "$CURRENT_JIRA_TICKET" ]]; then
		# Format: "PGF-123: feat(scope): message"
		# This enables JIRA Smart Commits
		commit_msg="${CURRENT_JIRA_TICKET}: ${commit_msg}"
		debug_log "Prepended JIRA ticket to commit message"
	fi

	echo "$commit_msg"
}

main() {
	debug_log "main() called"

	# Ensure we're in a git repository
	if ! git_is_repo; then
		debug_log "Not in a git repository, skipping"
		exit 0
	fi

	# Check if plugin should be active (must be GitHub repo)
	if ! git_is_github_repo; then
		debug_log "Not a GitHub repository, skipping"
		exit 0
	fi

	# Get current branch
	local current_branch
	current_branch="$(git_current_branch)"
	debug_log "Current branch: $current_branch"

	# Skip if on main branch (no feature work done)
	if git_is_main_branch "$current_branch"; then
		debug_log "On main branch, skipping commit/PR"
		exit 0
	fi

	# Only proceed if on a plugin-created branch
	if ! git_is_plugin_branch "$current_branch"; then
		debug_log "Not on a plugin-created branch ($current_branch), skipping"
		exit 0
	fi

	debug_log "On feature branch: $current_branch"

	# Get session state for context
	local STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"
	local session_prompt=""
	if [[ -f "${STATE_DIR}/current_session" ]]; then
		local session_id
		session_id="$(cat "${STATE_DIR}/current_session")"
		if [[ -f "${STATE_DIR}/${session_id}.json" ]]; then
			session_prompt="$(jq -r '.prompt // empty' "${STATE_DIR}/${session_id}.json" 2>/dev/null)"
		fi
	fi

	# Check if there are any changes to commit
	local changes
	changes="$(git status --porcelain)"
	if [[ -z "$changes" ]]; then
		debug_log "No changes to commit"
		# Still try to create PR if branch has commits
	else
		debug_log "Found uncommitted changes, staging and committing"

		# Get list of changed files for context
		local changed_files
		changed_files="$(git status --porcelain | awk '{print $2}')"

		# Stage all changes
		git add -A

		# Generate commit message
		local commit_msg
		commit_msg="$(generate_commit_message "$changed_files" "$session_prompt" "$current_branch")"

		debug_log "Commit message: ${commit_msg:0:100}..."

		# Create commit
		if git commit -m "$commit_msg"; then
			debug_log "Commit successful"
		else
			debug_log "Commit failed (might be no changes after staging)"
		fi
	fi

	# Push changes
	debug_log "Pushing to origin"
	if git push origin "$current_branch" 2>&1; then
		debug_log "Push successful"
	else
		debug_log "Push failed"
	fi

	# Check if PR already exists
	local existing_pr
	existing_pr="$(gh pr list --head "$current_branch" --json number --jq '.[0].number' 2>/dev/null || echo "")"

	if [[ -n "$existing_pr" ]]; then
		debug_log "PR #${existing_pr} already exists"
		echo "Pull request #${existing_pr} already exists for branch $current_branch"
		exit 0
	fi

	# Extract commit type for PR title
	local commit_type
	commit_type="$(get_commit_type_from_branch "$current_branch")"

	# Get the commit log for this branch (commits since base branch)
	local base_branch
	base_branch=$(git_find_base_branch 2>/dev/null || echo "main")
	local commit_log=""
	commit_log=$(git log --oneline "${base_branch}..HEAD" 2>/dev/null || git log --oneline -10 2>/dev/null || echo "")
	debug_log "Commit log: ${commit_log:0:200}..."

	# Generate PR title from branch description
	local branch_desc
	branch_desc="$(echo "$current_branch" | sed 's/^[^/]*\///' | tr '-' ' ')"

	# Include JIRA ticket in PR title for smart linking
	local pr_title
	if [[ -n "$CURRENT_JIRA_TICKET" ]]; then
		pr_title="${CURRENT_JIRA_TICKET}: ${commit_type}: ${branch_desc}"
	else
		pr_title="${commit_type}: ${branch_desc}"
	fi
	if [[ ${#pr_title} -gt 72 ]]; then
		pr_title="${pr_title:0:69}..."
	fi

	# Generate PR body using AI or fallback
	local pr_body=""

	# Try AI-generated summary first
	if [[ -n "$session_prompt" ]]; then
		pr_body=$(generate_ai_pr_summary "$session_prompt" "$commit_log" "$current_branch") || true
	fi

	# Fallback if AI failed or no session prompt
	if [[ -z "$pr_body" ]]; then
		debug_log "Using fallback PR summary"
		pr_body=$(generate_fallback_pr_summary "${session_prompt:-$branch_desc}" "$commit_log" "$commit_type")
	fi

	# Append metadata section
	local type_desc
	case "$commit_type" in
	feat) type_desc="A new feature" ;;
	fix) type_desc="A bug fix" ;;
	refactor) type_desc="Code refactoring" ;;
	perf) type_desc="Performance improvement" ;;
	test) type_desc="Tests" ;;
	docs) type_desc="Documentation" ;;
	build) type_desc="Build system changes" ;;
	ci) type_desc="CI configuration" ;;
	*) type_desc="Changes" ;;
	esac

	# Generate timestamp for this prompt
	local prompt_timestamp
	prompt_timestamp=$(format_timestamp)

	# Add JIRA ticket section if available
	local jira_section=""
	if [[ -n "$CURRENT_JIRA_TICKET" ]]; then
		local jira_url_display="$JIRA_TICKET_URL"
		if [[ -z "$jira_url_display" ]]; then
			# Try to construct URL from beads config
			local base_url
			base_url=$(jira_get_url)
			if [[ -n "$base_url" ]]; then
				jira_url_display="${base_url}/browse/${CURRENT_JIRA_TICKET}"
			fi
		fi

		jira_section="
## JIRA Ticket

| Field | Value |
|-------|-------|
| Ticket | [\`${CURRENT_JIRA_TICKET}\`](${jira_url_display}) |
"
	fi

	pr_body="${pr_body}
${jira_section}
---

## Metadata

| Field | Value |
|-------|-------|
| Type | \`${commit_type}\` - ${type_desc} |
| Branch | \`${current_branch}\` |
| Commits | $(echo "$commit_log" | wc -l | tr -d ' ') |

---

## Prompt History

<details>
<summary>📝 Prompt - ${prompt_timestamp}</summary>

\`\`\`
${session_prompt:-No prompt recorded}
\`\`\`

</details>
"

	# Create PR
	debug_log "Creating pull request"
	local pr_url=""
	if pr_url=$(gh pr create --title "$pr_title" --body "$pr_body" --head "$current_branch" 2>&1); then
		debug_log "PR created successfully"
		echo "Pull request created for branch $current_branch"

		# Comment on beads issue about the PR (if issue is set)
		if [[ -n "$CURRENT_BEADS_ISSUE" ]]; then
			debug_log "Commenting on beads issue $CURRENT_BEADS_ISSUE about PR"

			# Extract PR URL from output or construct it
			local actual_pr_url
			actual_pr_url=$(echo "$pr_url" | grep -oE 'https://github.com/[^[:space:]]+' | head -1)
			if [[ -z "$actual_pr_url" ]]; then
				# Try to get it from gh
				actual_pr_url=$(gh pr view --json url --jq '.url' 2>/dev/null || echo "")
			fi

			# Build a summary for beads comment
			local beads_comment="Pull request created for this issue:

**PR Title:** ${pr_title}

**PR URL:** ${actual_pr_url:-PR URL not available}

**JIRA Ticket:** ${CURRENT_JIRA_TICKET:-N/A}

**Summary:**
$(echo "$pr_body" | head -20 | sed 's/^/> /')

---
_Automated comment from agent-fork-join_"

			# Add comment via beads
			if beads_add_comment "$CURRENT_BEADS_ISSUE" "$beads_comment" 2>/dev/null; then
				debug_log "Successfully commented on beads issue"
				echo "Commented on beads issue $CURRENT_BEADS_ISSUE (JIRA: $CURRENT_JIRA_TICKET)"
			else
				debug_log "Failed to comment on beads issue"
			fi
		fi
	else
		debug_log "Failed to create PR"
	fi

	# Cleanup: remove tracked files list since session is complete
	local TRACKED_FILES="${STATE_DIR}/tracked_files.txt"
	if [[ -f "$TRACKED_FILES" ]]; then
		rm -f "$TRACKED_FILES"
		debug_log "Cleaned up tracked files list"
	fi

	debug_log "Stop hook completed"
}

debug_log "About to call main()"
main "$@"
debug_log "main() returned"
