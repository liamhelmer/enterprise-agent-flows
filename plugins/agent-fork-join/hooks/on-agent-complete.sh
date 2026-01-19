#!/usr/bin/env bash
# AgentComplete Hook - Triggered when an agent finishes work
#
# This hook:
# 1. Checks for changes in the agent's worktree
# 2. Requests a commit message from the agent
# 3. Commits changes and enqueues for merge
# 4. Handles conflict resolution if needed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/git-utils.sh"
source "${SCRIPT_DIR}/lib/daemon-client.sh"

# Configuration
STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"
DAEMON_SOCKET="${FORK_JOIN_DAEMON_SOCKET:-/tmp/merge-daemon.sock}"
MAX_RETRIES="${FORK_JOIN_MAX_RETRIES:-3}"

# Arguments
AGENT_ID="${1:-}"
COMMIT_MESSAGE="${2:-}"

main() {
	log_info "AgentComplete hook triggered for agent: $AGENT_ID"

	if [[ -z "$AGENT_ID" ]]; then
		log_error "Agent ID is required"
		exit 1
	fi

	# Get current session
	local session_id
	session_id="$(get_current_session)"

	if [[ -z "$session_id" ]]; then
		log_error "No active fork-join session"
		exit 1
	fi

	# Load session state
	local session_file="${STATE_DIR}/${session_id}.json"
	if [[ ! -f "$session_file" ]]; then
		log_error "Session file not found: $session_file"
		exit 1
	fi

	# Get agent info from session
	local agent_info
	agent_info="$(jq --arg id "$AGENT_ID" '.agents[] | select(.agent_id == $id)' "$session_file")"

	if [[ -z "$agent_info" ]]; then
		log_error "Agent not found in session: $AGENT_ID"
		exit 1
	fi

	local worktree
	local branch
	local feature_branch

	worktree="$(echo "$agent_info" | jq -r '.worktree')"
	branch="$(echo "$agent_info" | jq -r '.branch')"
	feature_branch="$(jq -r '.feature_branch' "$session_file")"

	# Check if worktree exists
	if [[ ! -d "$worktree" ]]; then
		log_error "Worktree not found: $worktree"
		exit 1
	fi

	# Check for changes
	log_info "Checking for changes in worktree: $worktree"

	cd "$worktree"

	local has_changes=false
	if [[ -n "$(git status --porcelain)" ]]; then
		has_changes=true
	fi

	if [[ "$has_changes" == "false" ]]; then
		log_info "No changes detected, cleaning up"
		cleanup_agent "$session_id" "$AGENT_ID" "$worktree" "$branch"

		cat <<EOF
{
    "agent_complete": true,
    "agent_id": "${AGENT_ID}",
    "changes": false,
    "merged": false
}
EOF
		exit 0
	fi

	log_info "Changes detected, preparing commit"

	# Use provided commit message or generate one
	if [[ -z "$COMMIT_MESSAGE" ]]; then
		# Request commit message from caller
		cat <<EOF
{
    "agent_complete": false,
    "agent_id": "${AGENT_ID}",
    "changes": true,
    "needs_commit_message": true,
    "changed_files": $(git status --porcelain | jq -R -s 'split("\n") | map(select(length > 0))')
}
EOF
		exit 0
	fi

	# Stage all changes
	git add -A

	# Commit changes
	git commit -m "$COMMIT_MESSAGE" --author="Agent ${AGENT_ID} for $(git config --get user.email)"

	local commit_sha
	commit_sha="$(git rev-parse HEAD)"

	log_info "Committed changes: $commit_sha"

	# Update session state
	jq --arg id "$AGENT_ID" --arg msg "$COMMIT_MESSAGE" --arg sha "$commit_sha" \
		'(.agents[] | select(.agent_id == $id)) |= . + {commit_message: $msg, commit_sha: $sha, status: "COMMITTED"}' \
		"$session_file" >"${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

	# Enqueue for merge
	log_info "Enqueueing branch for merge: $branch"

	local enqueue_result
	enqueue_result="$(daemon_send "$(
		cat <<EOF
{
    "type": "ENQUEUE",
    "agent_id": "${AGENT_ID}",
    "session_id": "${session_id}",
    "branch": "${branch}",
    "worktree": "${worktree}",
    "target_branch": "${feature_branch}"
}
EOF
	)")"

	local enqueue_status
	enqueue_status="$(echo "$enqueue_result" | jq -r '.status // "ERROR"')"

	if [[ "$enqueue_status" != "OK" ]]; then
		log_error "Failed to enqueue merge: $enqueue_result"

		cat <<EOF
{
    "agent_complete": false,
    "agent_id": "${AGENT_ID}",
    "changes": true,
    "error": "Failed to enqueue merge",
    "details": $(echo "$enqueue_result" | jq -c .)
}
EOF
		exit 1
	fi

	local queue_position
	queue_position="$(echo "$enqueue_result" | jq -r '.position // 0')"

	log_info "Enqueued at position: $queue_position"

	# Wait for merge result (could be async, but for now we'll output pending)
	cat <<EOF
{
    "agent_complete": true,
    "agent_id": "${AGENT_ID}",
    "changes": true,
    "commit_sha": "${commit_sha}",
    "merge_queued": true,
    "queue_position": ${queue_position},
    "awaiting_merge": true
}
EOF

	log_info "Agent $AGENT_ID complete, merge queued"
}

# Get current session ID
get_current_session() {
	local session_file="${STATE_DIR}/current_session"
	if [[ -f "$session_file" ]]; then
		cat "$session_file"
	fi
}

# Cleanup an agent's worktree and branch
cleanup_agent() {
	local session_id="$1"
	local agent_id="$2"
	local worktree="$3"
	local branch="$4"

	log_info "Cleaning up agent: $agent_id"

	# Return to original directory
	cd - >/dev/null 2>&1 || true

	# Remove worktree
	git worktree remove "$worktree" --force 2>/dev/null || true

	# Delete agent branch
	git branch -D "$branch" 2>/dev/null || true

	# Update session state
	local session_file="${STATE_DIR}/${session_id}.json"
	jq --arg id "$agent_id" \
		'(.agents[] | select(.agent_id == $id)) |= . + {status: "CLEANED_UP"}' \
		"$session_file" >"${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"

	# Deregister from daemon
	daemon_send '{"type":"DEQUEUE","agent_id":"'"$agent_id"'"}' >/dev/null 2>&1 || true

	log_info "Agent $agent_id cleaned up"
}

main "$@"
