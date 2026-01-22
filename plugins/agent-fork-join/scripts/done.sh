#!/usr/bin/env bash
# /done command - Complete local branch workflow
#
# This script (LOCAL ONLY - does not modify remote):
# 1. Checks if current PR was merged
# 2. Switches to main branch
# 3. Pulls latest changes
# 4. Deletes local feature branch (if PR was merged)
# 5. Signals to run /compact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities if available
if [[ -f "${SCRIPT_DIR}/../hooks/lib/common.sh" ]]; then
	source "${SCRIPT_DIR}/../hooks/lib/common.sh"
fi

if [[ -f "${SCRIPT_DIR}/../hooks/lib/git-utils.sh" ]]; then
	source "${SCRIPT_DIR}/../hooks/lib/git-utils.sh"
fi

# Debug logging
DEBUG_LOG="/tmp/fork-join-done-debug.log"
debug_log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DONE] $*" >>"${DEBUG_LOG}"
	echo "[DONE] $*" >&2
}

# Output for user
output() {
	echo "$*"
}

# Get default branch name
get_default_branch() {
	local default
	default=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d: -f2 | tr -d ' ')

	if [[ -n "$default" ]]; then
		echo "$default"
	elif git show-ref --verify --quiet refs/heads/main; then
		echo "main"
	elif git show-ref --verify --quiet refs/heads/master; then
		echo "master"
	else
		echo "main"
	fi
}

# Check if current branch is a feature branch (Angular-style)
is_feature_branch() {
	local branch="$1"
	[[ "$branch" =~ ^(build|ci|docs|feat|fix|perf|refactor|test)/ ]]
}

# Global to track if we should delete the local branch
SHOULD_DELETE_LOCAL_BRANCH=""

# Global to track JIRA ticket for this session
CURRENT_JIRA_TICKET=""
JIRA_TICKET_URL=""

# Get current JIRA ticket if available
get_jira_ticket() {
	if [[ -f "${SCRIPT_DIR}/../hooks/lib/common.sh" ]]; then
		if current_ticket=$(jira_get_current_ticket 2>/dev/null); then
			CURRENT_JIRA_TICKET="$current_ticket"
			JIRA_TICKET_URL=$(jira_get_ticket_field "$current_ticket" "url" 2>/dev/null || echo "")
			debug_log "JIRA ticket detected: $CURRENT_JIRA_TICKET"
		fi
	fi
}

# Check PR status (LOCAL ONLY - no remote modifications)
# Sets SHOULD_DELETE_LOCAL_BRANCH if the PR was merged
check_pr_status() {
	local current_branch="$1"

	if ! is_feature_branch "$current_branch"; then
		debug_log "Not on a feature branch, skipping PR check"
		return 0
	fi

	# Check if gh CLI is available
	if ! command -v gh >/dev/null 2>&1; then
		output "Warning: gh CLI not available, cannot check PR status"
		return 0
	fi

	# Get PR number for current branch - check all PRs including closed/merged
	local pr_number
	pr_number=$(gh pr list --head "$current_branch" --state all --json number --jq '.[0].number' 2>/dev/null || echo "")

	if [[ -z "$pr_number" ]]; then
		debug_log "No PR found for branch $current_branch"
		output "No PR found for branch: $current_branch"
		return 0
	fi

	# Check PR state
	local pr_state
	pr_state=$(gh pr view "$pr_number" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")

	case "$pr_state" in
	"OPEN")
		output "PR #${pr_number} is still open."
		output "Merge the PR on GitHub when ready, then run /done again."
		debug_log "PR #${pr_number} is open"
		;;
	"MERGED")
		output "PR #${pr_number} was merged."
		debug_log "PR #${pr_number} already merged"
		# Mark local branch for deletion since PR was merged
		SHOULD_DELETE_LOCAL_BRANCH="$current_branch"

		# Comment on JIRA ticket that PR was merged
		if [[ -n "$CURRENT_JIRA_TICKET" ]]; then
			debug_log "Commenting on JIRA ticket about merge"
			local merge_comment="Pull request merged.

**PR:** #${pr_number}

---
_Automated comment from agent-fork-join_"
			if jira_add_comment "$CURRENT_JIRA_TICKET" "$merge_comment" 2>/dev/null; then
				output "Commented on JIRA ticket $CURRENT_JIRA_TICKET about merge."
			fi
		fi
		;;
	"CLOSED")
		# Check if it was merged by looking at the merge commit
		local merged_at
		merged_at=$(gh pr view "$pr_number" --json mergedAt --jq '.mergedAt' 2>/dev/null || echo "null")

		if [[ "$merged_at" != "null" && -n "$merged_at" ]]; then
			output "PR #${pr_number} was merged."
			debug_log "PR #${pr_number} was merged (closed state)"
			SHOULD_DELETE_LOCAL_BRANCH="$current_branch"

			# Comment on JIRA ticket that PR was merged
			if [[ -n "$CURRENT_JIRA_TICKET" ]]; then
				debug_log "Commenting on JIRA ticket about merge"
				local merge_comment="Pull request merged.

**PR:** #${pr_number}

---
_Automated comment from agent-fork-join_"
				if jira_add_comment "$CURRENT_JIRA_TICKET" "$merge_comment" 2>/dev/null; then
					output "Commented on JIRA ticket $CURRENT_JIRA_TICKET about merge."
				fi
			fi
		else
			output "PR #${pr_number} is closed (not merged)."
			debug_log "PR #${pr_number} is closed without merge"
		fi
		;;
	*)
		output "PR #${pr_number} has unknown state: $pr_state"
		debug_log "PR #${pr_number} has unknown state: $pr_state"
		;;
	esac

	return 0
}

# Delete a local branch
delete_local_branch() {
	local branch="$1"
	local default_branch="$2"

	if [[ -z "$branch" ]]; then
		return 0
	fi

	# Don't delete the default branch
	if [[ "$branch" == "$default_branch" ]]; then
		return 0
	fi

	# Check if branch exists locally
	if ! git show-ref --verify --quiet "refs/heads/$branch"; then
		debug_log "Branch $branch doesn't exist locally, nothing to delete"
		return 0
	fi

	output "Deleting local branch: $branch..."

	if git branch -D "$branch" 2>&1; then
		output "Deleted local branch: $branch"
		debug_log "Deleted local branch: $branch"
	else
		output "Warning: Could not delete local branch $branch"
		debug_log "Failed to delete local branch: $branch"
	fi

	# Also try to delete remote tracking branch if it exists
	if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		git branch -dr "origin/$branch" 2>/dev/null || true
		debug_log "Deleted remote tracking branch: origin/$branch"
	fi

	return 0
}

# Switch to default branch
switch_to_default_branch() {
	local default_branch="$1"
	local current_branch
	current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

	if [[ "$current_branch" == "$default_branch" ]]; then
		output "Already on $default_branch branch."
		return 0
	fi

	output "Switching to $default_branch branch..."

	# Check for uncommitted changes
	if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
		output "Warning: You have uncommitted changes. Stashing them..."
		git stash push -m "Auto-stash before /done command"
	fi

	if git checkout "$default_branch" 2>&1; then
		output "Switched to $default_branch"
		debug_log "Switched to $default_branch"
	else
		output "Error: Failed to switch to $default_branch"
		return 1
	fi

	return 0
}

# Pull latest changes
pull_latest() {
	local default_branch="$1"

	output "Pulling latest changes from origin/$default_branch..."

	# Fetch first to see what's coming
	git fetch origin "$default_branch" 2>/dev/null || true

	# Attempt pull
	local pull_output
	if pull_output=$(git pull origin "$default_branch" 2>&1); then
		if [[ "$pull_output" == *"Already up to date"* ]]; then
			output "Already up to date."
		else
			output "Successfully pulled latest changes."
		fi
		debug_log "Pull successful"
		return 0
	else
		output "Warning: Pull encountered issues:"
		echo "$pull_output"

		# Check for conflicts
		if [[ "$pull_output" == *"CONFLICT"* ]] || [[ "$pull_output" == *"conflict"* ]]; then
			output ""
			output "Merge conflicts detected. Attempting automatic resolution..."

			# Try to auto-resolve simple conflicts
			if git checkout --theirs . 2>/dev/null; then
				git add -A
				if git commit -m "Auto-resolved conflicts during /done" 2>/dev/null; then
					output "Conflicts resolved automatically by accepting remote changes."
					return 0
				fi
			fi

			output "Could not auto-resolve all conflicts. Please resolve manually:"
			git status --short | grep "^UU\|^AA\|^DD" || true
			return 1
		fi

		return 1
	fi
}

# Clean up session state
cleanup_session() {
	local STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"

	if [[ -d "$STATE_DIR" ]]; then
		# Clear current session marker
		rm -f "${STATE_DIR}/current_session"
		rm -f "${STATE_DIR}/tracked_files.txt"
		debug_log "Cleaned up session state"
	fi
}

# Clean up JIRA ticket tracking
cleanup_jira_ticket() {
	if [[ -n "$CURRENT_JIRA_TICKET" ]]; then
		# Clear the current-ticket symlink
		jira_clear_current_ticket 2>/dev/null || true
		debug_log "Cleared JIRA current-ticket symlink"
	fi
}

# Ask user about JIRA ticket status change
# This outputs instructions for the Claude agent to ask the user
# Returns: status to set, or empty if no change
ask_jira_status_change() {
	if [[ -z "$CURRENT_JIRA_TICKET" ]]; then
		return 0
	fi

	output ""
	output "=== JIRA Ticket Status ==="
	output ""
	output "Current JIRA ticket: $CURRENT_JIRA_TICKET"
	if [[ -n "$JIRA_TICKET_URL" ]]; then
		output "URL: $JIRA_TICKET_URL"
	fi
	output ""
	output "JIRA_TICKET_STATUS_QUESTION=true"
	output "JIRA_TICKET_ID=$CURRENT_JIRA_TICKET"
	output ""
	output "The Claude agent should use AskUserQuestion to ask:"
	output "  Question: 'Would you like to update the JIRA ticket status?'"
	output "  Options:"
	output "    - 'Done' - Mark the ticket as done"
	output "    - 'In Review' - Mark as in review"
	output "    - 'No change' - Leave status unchanged"
	output ""
}

# Main function
main() {
	debug_log "=== /done command started ==="

	# Ensure we're in a git repository
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		output "Error: Not in a git repository"
		exit 1
	fi

	# Get JIRA ticket info early
	get_jira_ticket

	local current_branch
	current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
	debug_log "Current branch: $current_branch"

	local default_branch
	default_branch=$(get_default_branch)
	debug_log "Default branch: $default_branch"

	output ""
	output "=== Completing Branch Workflow ==="
	output ""

	# Step 1: Check PR status (sets SHOULD_DELETE_LOCAL_BRANCH if PR was merged)
	# This also comments on JIRA if PR was merged
	check_pr_status "$current_branch"

	output ""

	# Step 2: Ask about JIRA ticket status (if we have a ticket and PR was merged)
	if [[ -n "$CURRENT_JIRA_TICKET" && -n "$SHOULD_DELETE_LOCAL_BRANCH" ]]; then
		ask_jira_status_change
	fi

	# Step 3: Switch to default branch
	if ! switch_to_default_branch "$default_branch"; then
		output ""
		output "Failed to switch to $default_branch. Please check your git state."
		exit 1
	fi

	output ""

	# Step 4: Pull latest changes
	if ! pull_latest "$default_branch"; then
		output ""
		output "Pull failed. Please resolve any conflicts manually."
		exit 1
	fi

	output ""

	# Step 5: Delete local feature branch if marked for deletion
	if [[ -n "$SHOULD_DELETE_LOCAL_BRANCH" ]]; then
		delete_local_branch "$SHOULD_DELETE_LOCAL_BRANCH" "$default_branch"
		output ""
	fi

	# Step 6: Clean up session state
	cleanup_session

	# Step 7: Clean up JIRA ticket tracking (if PR was merged)
	if [[ -n "$SHOULD_DELETE_LOCAL_BRANCH" ]]; then
		cleanup_jira_ticket
	fi

	output ""
	output "=== Workflow Complete ==="
	output ""
	output "Run /compact to consolidate conversation history."
	output ""

	# Return a signal that /compact should be run
	echo "RUN_COMPACT=true"

	debug_log "=== /done command completed ==="
}

main "$@"
