#!/usr/bin/env bash
# Stop Hook - Commits changes and creates PR when session completes
#
# This hook:
# 1. Checks if we're on a feature branch
# 2. Commits any uncommitted changes
# 3. Pushes to remote
# 4. Creates a PR if one doesn't exist

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/fork-join-hook-debug.log"
debug_log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STOP] $*" >>"${DEBUG_LOG}"
	echo "[HOOK DEBUG] [STOP] $*" >&2
}

debug_log "=== Stop hook started ==="
debug_log "PWD: $(pwd)"

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

	# Check if there are any changes to commit
	if ! git status --porcelain | grep -q .; then
		debug_log "No changes to commit"
		# Still try to create PR if branch has commits
	else
		debug_log "Found uncommitted changes, staging and committing"

		# Stage all changes
		git add -A

		# Create commit message based on session state if available
		local commit_msg="Add modules created during session"
		local STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"
		if [[ -f "${STATE_DIR}/current_session" ]]; then
			local session_id
			session_id="$(cat "${STATE_DIR}/current_session")"
			if [[ -f "${STATE_DIR}/${session_id}.json" ]]; then
				local prompt
				prompt="$(jq -r '.prompt // empty' "${STATE_DIR}/${session_id}.json" 2>/dev/null | head -1 | cut -c1-50)"
				if [[ -n "$prompt" ]]; then
					commit_msg="Session work: ${prompt}..."
				fi
			fi
		fi

		debug_log "Committing with message: $commit_msg"
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

	# Create PR
	debug_log "Creating pull request"
	local pr_title="Feature: $current_branch"
	local pr_body="Automated PR created by agent-fork-join plugin.

## Changes
Files created during the session.

## Branch
\`$current_branch\`
"

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
