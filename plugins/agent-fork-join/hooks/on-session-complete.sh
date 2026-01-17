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

	# Check if claude CLI is available
	if ! command -v claude >/dev/null 2>&1; then
		debug_log "Claude CLI not available, falling back to heuristic"
		return 1
	fi

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
	# Use 10s timeout to prevent blocking
	export FORK_JOIN_HOOK_CONTEXT=1
	local commit_msg
	if command -v timeout >/dev/null 2>&1; then
		commit_msg=$(echo "$ai_prompt" | timeout 10 claude --print --model haiku -p - 2>/dev/null) || true
	elif command -v gtimeout >/dev/null 2>&1; then
		commit_msg=$(echo "$ai_prompt" | gtimeout 10 claude --print --model haiku -p - 2>/dev/null) || true
	else
		# Fallback: run without timeout but with background kill after 10s
		local tmp_output
		tmp_output=$(mktemp)
		(echo "$ai_prompt" | claude --print --model haiku -p - >"$tmp_output" 2>/dev/null) &
		local pid=$!
		local waited=0
		while kill -0 "$pid" 2>/dev/null && [[ $waited -lt 10 ]]; do
			sleep 1
			waited=$((waited + 1))
		done
		if kill -0 "$pid" 2>/dev/null; then
			debug_log "AI call timed out after 10s, killing"
			kill "$pid" 2>/dev/null || true
			commit_msg=""
		else
			commit_msg=$(cat "$tmp_output")
		fi
		rm -f "$tmp_output"
	fi
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
generate_commit_message() {
	local changes="$1"
	local session_prompt="$2"
	local branch_name="$3"

	# Try AI first
	local commit_msg
	if commit_msg="$(generate_ai_commit_message "$changes" "$session_prompt" "$branch_name")"; then
		echo "$commit_msg"
		return 0
	fi

	# Fall back to heuristic
	debug_log "Falling back to heuristic commit message generation"
	generate_heuristic_commit_message "$changes" "$session_prompt" "$branch_name"
}

main() {
	debug_log "main() called"

	# Ensure we're in a git repository
	if ! git_is_repo; then
		debug_log "Not in a git repository, skipping"
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

	debug_log "On feature branch: $current_branch"

	# Get session state for context
	local STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"
	local session_prompt=""
	if [[ -f "${STATE_DIR}/current_session" ]]; then
		local session_id
		session_id="$(cat "${STATE_DIR}/current_session")"
		if [[ -f "${STATE_DIR}/${session_id}.json" ]]; then
			session_prompt="$(jq -r '.prompt // empty' "${STATE_DIR}/${session_id}.json" 2>/dev/null | head -5)"
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

	# Generate PR title and body
	local branch_desc
	branch_desc="$(echo "$current_branch" | sed 's/^[^/]*\///' | tr '-' ' ')"

	local pr_title="${commit_type}: ${branch_desc}"
	if [[ ${#pr_title} -gt 72 ]]; then
		pr_title="${pr_title:0:69}..."
	fi

	# Generate PR body
	local pr_body
	pr_body="## Summary
${branch_desc}

## Type
\`${commit_type}\` - $(
		case "$commit_type" in
		feat) echo "A new feature" ;;
		fix) echo "A bug fix" ;;
		refactor) echo "Code refactoring" ;;
		perf) echo "Performance improvement" ;;
		test) echo "Tests" ;;
		docs) echo "Documentation" ;;
		build) echo "Build system changes" ;;
		ci) echo "CI configuration" ;;
		*) echo "Changes" ;;
		esac
	)

## Branch
\`$current_branch\`
"

	if [[ -n "$session_prompt" ]]; then
		pr_body="${pr_body}
## Original Task
\`\`\`
${session_prompt:0:500}
\`\`\`
"
	fi

	# Create PR
	debug_log "Creating pull request"
	if gh pr create --title "$pr_title" --body "$pr_body" --head "$current_branch" 2>&1; then
		debug_log "PR created successfully"
		echo "Pull request created for branch $current_branch"
	else
		debug_log "Failed to create PR"
	fi

	debug_log "Stop hook completed"
}

debug_log "About to call main()"
main "$@"
debug_log "main() returned"
