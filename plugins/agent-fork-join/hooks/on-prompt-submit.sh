#!/usr/bin/env bash
# UserPromptSubmit Hook - Creates and pushes feature branch immediately
#
# This hook:
# 1. Detects if the prompt will make code changes
# 2. Creates a feature branch if on main/master
# 3. IMMEDIATELY pushes the branch to origin (so we know work has started)

set -euo pipefail

# Debug logging - write to stderr and a debug file
DEBUG_LOG="/tmp/fork-join-hook-debug.log"
debug_log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"${DEBUG_LOG}"
	echo "[HOOK DEBUG] $*" >&2
}

debug_log "=== UserPromptSubmit hook started ==="
debug_log "PWD: $(pwd)"
debug_log "BASH_SOURCE: ${BASH_SOURCE[0]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
debug_log "SCRIPT_DIR: ${SCRIPT_DIR}"

# Source dependencies with error handling
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
	source "${SCRIPT_DIR}/lib/common.sh"
	debug_log "Sourced common.sh"
else
	debug_log "ERROR: common.sh not found at ${SCRIPT_DIR}/lib/common.sh"
	echo "ERROR: common.sh not found" >&2
	exit 1
fi

if [[ -f "${SCRIPT_DIR}/lib/git-utils.sh" ]]; then
	source "${SCRIPT_DIR}/lib/git-utils.sh"
	debug_log "Sourced git-utils.sh"
else
	debug_log "ERROR: git-utils.sh not found at ${SCRIPT_DIR}/lib/git-utils.sh"
	echo "ERROR: git-utils.sh not found" >&2
	exit 1
fi

# Configuration
FEATURE_BRANCH_PREFIX="${FORK_JOIN_FEATURE_PREFIX:-feature/}"

# Read the input from stdin or argument
# Claude Code hooks receive JSON with structure: {"session_id": "...", "prompt": "...", ...}
RAW_INPUT="${1:-}"
if [[ -z "$RAW_INPUT" ]] && [[ ! -t 0 ]]; then
	RAW_INPUT="$(cat)"
fi

# Extract the actual prompt from the JSON input
# If jq is available, use it for proper parsing; otherwise use grep/sed
if command -v jq >/dev/null 2>&1; then
	PROMPT=$(echo "$RAW_INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")
else
	# Fallback: extract prompt field using sed (less reliable but works for simple cases)
	PROMPT=$(echo "$RAW_INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

# If we couldn't extract the prompt, use the raw input (for backwards compatibility)
if [[ -z "$PROMPT" ]]; then
	debug_log "Could not extract prompt from JSON, using raw input"
	PROMPT="$RAW_INPUT"
fi

debug_log "Extracted prompt: '${PROMPT:0:100}...'"

# Keywords that indicate the prompt will make changes
CHANGE_KEYWORDS=(
	"implement" "add" "create" "fix" "update" "modify" "refactor"
	"remove" "delete" "change" "write" "build" "develop" "spawn"
)

# Check if prompt indicates changes
prompt_will_make_changes() {
	local prompt_lower
	prompt_lower="$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')"

	for keyword in "${CHANGE_KEYWORDS[@]}"; do
		if [[ "$prompt_lower" == *"$keyword"* ]]; then
			return 0
		fi
	done
	return 1
}

# Generate a branch name from prompt
generate_branch_name() {
	local slug
	# Take only the first line, convert to lowercase, remove non-alphanumeric except spaces
	# Then take first 3 words and join with hyphens
	slug=$(echo "$PROMPT" | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '\n\r' | sed 's/[^a-z0-9 ]//g' | awk '{print $1"-"$2"-"$3}' | sed 's/-*$//' | cut -c1-50)

	if [[ -z "$slug" || "$slug" == "--" ]]; then
		slug="task-$(date +%s)"
	fi

	echo "${FEATURE_BRANCH_PREFIX}${slug}"
}

main() {
	debug_log "main() called"
	log_info "UserPromptSubmit hook triggered"

	debug_log "PROMPT value: '${PROMPT:0:100}...'" # First 100 chars

	# Check if prompt will make changes
	if ! prompt_will_make_changes; then
		debug_log "Prompt does NOT appear to make changes, skipping"
		log_debug "Prompt does not appear to make changes, skipping"
		exit 0
	fi

	debug_log "Prompt WILL make changes"
	log_info "Detected change-making prompt"

	# Ensure we're in a git repository
	if ! git_is_repo; then
		debug_log "ERROR: Not in a git repository"
		log_error "Not in a git repository"
		exit 1
	fi
	debug_log "Confirmed: in a git repository"

	# Get current branch
	local current_branch
	current_branch="$(git_current_branch)"
	debug_log "Current branch: $current_branch"

	# Session state directory
	local STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"

	# Check if we need to create a feature branch
	if git_is_main_branch "$current_branch"; then
		debug_log "On main branch, will create feature branch"
		log_info "Currently on main branch ($current_branch), creating feature branch"

		local feature_branch
		feature_branch="$(generate_branch_name)"
		debug_log "Generated branch name: $feature_branch"

		# Create and checkout feature branch
		debug_log "Running: git checkout -b $feature_branch"
		if git checkout -b "$feature_branch" 2>&1; then
			debug_log "Branch created successfully"
			log_info "Created feature branch: $feature_branch"
		else
			debug_log "ERROR: Failed to create branch"
			log_error "Failed to create branch"
			exit 1
		fi

		# IMMEDIATELY push the branch to origin so we know work has started
		debug_log "Running: git push -u origin $feature_branch"
		log_info "Pushing feature branch to origin..."
		if git push -u origin "$feature_branch" 2>&1; then
			debug_log "Push successful"
			log_info "Feature branch pushed successfully"
		else
			debug_log "Push failed (may not have remote)"
			log_warn "Failed to push feature branch (may not have remote)"
		fi

		# Create session state for other hooks to use
		local session_id
		session_id="session-$(date +%s)"
		local timestamp
		timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

		mkdir -p "$STATE_DIR"
		echo "$session_id" >"${STATE_DIR}/current_session"

		cat >"${STATE_DIR}/${session_id}.json" <<SESS_EOF
{
    "session_id": "$session_id",
    "feature_branch": "$feature_branch",
    "base_branch": "$current_branch",
    "prompt": $(echo "$PROMPT" | jq -Rs .),
    "state": "STARTED",
    "started_at": "$timestamp",
    "agents": [],
    "merged_count": 0,
    "conflict_count": 0
}
SESS_EOF

		debug_log "Created session state: $session_id"

		# Output for Claude Code
		echo "Feature branch '$feature_branch' created and pushed to origin."
		echo "Session ID: $session_id"
	else
		debug_log "Already on feature branch: $current_branch"
		log_info "Already on feature branch: $current_branch"
		echo "Already on feature branch: $current_branch"
	fi

	debug_log "Hook completed successfully"
	log_info "Fork-join hook completed"
}

debug_log "About to call main()"
main "$@"
debug_log "main() returned"
