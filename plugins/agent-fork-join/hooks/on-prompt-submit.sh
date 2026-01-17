#!/usr/bin/env bash
# UserPromptSubmit Hook - Creates and pushes feature branch immediately
#
# This hook:
# 1. Detects if the prompt will make code changes
# 2. Uses AI to generate a branch name following Angular commit conventions
# 3. Creates a feature branch if on main/master
# 4. IMMEDIATELY pushes the branch to origin (so we know work has started)

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

# Valid Angular commit types for branch prefixes
VALID_TYPES=("build" "ci" "docs" "feat" "fix" "perf" "refactor" "test")

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

# Guard against recursive hook calls
# Check if we're already in a hook context (set by our own AI calls)
if [[ "${FORK_JOIN_HOOK_CONTEXT:-}" == "1" ]]; then
	debug_log "Already in hook context, skipping to prevent recursion"
	exit 0
fi

# Keywords that indicate the prompt will make changes
CHANGE_KEYWORDS=(
	"implement" "add" "create" "fix" "update" "modify" "refactor"
	"remove" "delete" "change" "write" "build" "develop" "spawn"
	"test" "optimize" "improve" "document" "configure" "setup"
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

# Check if user specified a branch name in the prompt
extract_user_branch_name() {
	local prompt_lower
	prompt_lower="$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')"

	# Look for patterns like "branch: xyz", "on branch xyz", "branch name: xyz"
	local branch_name=""

	# Pattern: "branch: <name>" or "branch name: <name>"
	if [[ "$prompt_lower" =~ branch[[:space:]]*name?[[:space:]]*:[[:space:]]*([a-z0-9/_-]+) ]]; then
		branch_name="${BASH_REMATCH[1]}"
	# Pattern: "on branch <name>"
	elif [[ "$prompt_lower" =~ on[[:space:]]+branch[[:space:]]+([a-z0-9/_-]+) ]]; then
		branch_name="${BASH_REMATCH[1]}"
	# Pattern: "use branch <name>"
	elif [[ "$prompt_lower" =~ use[[:space:]]+branch[[:space:]]+([a-z0-9/_-]+) ]]; then
		branch_name="${BASH_REMATCH[1]}"
	fi

	echo "$branch_name"
}

# Validate that branch name starts with a valid Angular type
validate_branch_type() {
	local branch_name="$1"

	for type in "${VALID_TYPES[@]}"; do
		if [[ "$branch_name" == "${type}/"* ]]; then
			return 0
		fi
	done
	return 1
}

# Use Claude AI to generate a branch name following Angular conventions
generate_ai_branch_name() {
	local prompt_text="$1"
	local ai_branch=""

	# Check if claude CLI is available
	if ! command -v claude >/dev/null 2>&1; then
		debug_log "Claude CLI not available, falling back to heuristic"
		return 1
	fi

	debug_log "Using Claude AI to generate branch name..."

	# Create a prompt for Claude to generate the branch name
	local ai_prompt
	ai_prompt="$(
		cat <<'AIPROMPT'
Analyze this task description and generate a git branch name following Angular commit conventions.

VALID TYPES (choose ONE):
- feat: A new feature
- fix: A bug fix
- refactor: Code change that neither fixes a bug nor adds a feature
- perf: Performance improvement
- test: Adding or correcting tests
- docs: Documentation only changes
- build: Build system or dependency changes
- ci: CI configuration changes

RULES:
1. Branch name format: <type>/<short-description>
2. Use lowercase only
3. Use hyphens between words (no spaces or underscores)
4. Keep description under 30 characters
5. Be specific but concise

TASK DESCRIPTION:
AIPROMPT
	)"

	# Append the actual prompt
	ai_prompt="${ai_prompt}
${prompt_text}

OUTPUT ONLY THE BRANCH NAME, nothing else. Example: feat/add-user-auth"

	# Call Claude CLI with minimal settings and 10s timeout
	# Use --print to get output, -p for prompt, --model haiku for speed
	# Set FORK_JOIN_HOOK_CONTEXT to prevent recursive hook calls
	export FORK_JOIN_HOOK_CONTEXT=1
	local raw_response
	# Use timeout to prevent blocking (10 seconds max)
	if command -v timeout >/dev/null 2>&1; then
		raw_response=$(echo "$ai_prompt" | timeout 10 claude --print --model haiku -p - 2>/dev/null) || true
	elif command -v gtimeout >/dev/null 2>&1; then
		raw_response=$(echo "$ai_prompt" | gtimeout 10 claude --print --model haiku -p - 2>/dev/null) || true
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
			raw_response=""
		else
			raw_response=$(cat "$tmp_output")
		fi
		rm -f "$tmp_output"
	fi
	unset FORK_JOIN_HOOK_CONTEXT
	debug_log "AI raw response: '${raw_response:0:100}...'"

	ai_branch=$(echo "$raw_response" | tr -d '\n\r' | head -1)

	# Clean up the response - extract just the branch name
	ai_branch=$(echo "$ai_branch" | grep -oE '^(build|ci|docs|feat|fix|perf|refactor|test)/[a-z0-9-]+' | head -1)
	debug_log "AI cleaned branch: '$ai_branch'"

	if [[ -n "$ai_branch" ]] && validate_branch_type "$ai_branch"; then
		debug_log "AI generated branch name: $ai_branch"
		echo "$ai_branch"
		return 0
	else
		debug_log "AI response was invalid or empty: '$ai_branch'"
		return 1
	fi
}

# Heuristic fallback to determine commit type from prompt
determine_type_heuristic() {
	local prompt_lower
	prompt_lower="$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')"

	# Check for type indicators in order of specificity
	if [[ "$prompt_lower" == *"fix"* ]] || [[ "$prompt_lower" == *"bug"* ]] || [[ "$prompt_lower" == *"error"* ]] || [[ "$prompt_lower" == *"issue"* ]]; then
		echo "fix"
	elif [[ "$prompt_lower" == *"test"* ]] || [[ "$prompt_lower" == *"spec"* ]]; then
		echo "test"
	elif [[ "$prompt_lower" == *"document"* ]] || [[ "$prompt_lower" == *"readme"* ]] || [[ "$prompt_lower" == *"doc"* ]]; then
		echo "docs"
	elif [[ "$prompt_lower" == *"refactor"* ]] || [[ "$prompt_lower" == *"restructure"* ]] || [[ "$prompt_lower" == *"reorganize"* ]] || [[ "$prompt_lower" == *"clean"* ]]; then
		echo "refactor"
	elif [[ "$prompt_lower" == *"performance"* ]] || [[ "$prompt_lower" == *"optimize"* ]] || [[ "$prompt_lower" == *"speed"* ]] || [[ "$prompt_lower" == *"faster"* ]]; then
		echo "perf"
	elif [[ "$prompt_lower" == *"build"* ]] || [[ "$prompt_lower" == *"dependency"* ]] || [[ "$prompt_lower" == *"package"* ]]; then
		echo "build"
	elif [[ "$prompt_lower" == *"ci"* ]] || [[ "$prompt_lower" == *"pipeline"* ]] || [[ "$prompt_lower" == *"workflow"* ]] || [[ "$prompt_lower" == *"github action"* ]]; then
		echo "ci"
	else
		# Default to feat for new functionality
		echo "feat"
	fi
}

# Generate a branch name using heuristics (fallback when AI is unavailable)
generate_heuristic_branch_name() {
	local commit_type
	commit_type="$(determine_type_heuristic)"

	# Extract key words from prompt for description
	local slug
	slug=$(echo "$PROMPT" | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '\n\r' | sed 's/[^a-z0-9 ]//g' | awk '{
		# Skip common words and the type we detected
		skip["the"] = 1; skip["a"] = 1; skip["an"] = 1; skip["to"] = 1;
		skip["and"] = 1; skip["or"] = 1; skip["for"] = 1; skip["in"] = 1;
		skip["on"] = 1; skip["with"] = 1; skip["that"] = 1; skip["this"] = 1;
		skip["is"] = 1; skip["are"] = 1; skip["be"] = 1; skip["will"] = 1;
		skip["please"] = 1; skip["can"] = 1; skip["you"] = 1; skip["i"] = 1;
		skip["implement"] = 1; skip["add"] = 1; skip["create"] = 1;
		skip["fix"] = 1; skip["update"] = 1; skip["modify"] = 1;
		words = ""
		count = 0
		for (i = 1; i <= NF && count < 3; i++) {
			if (!($i in skip) && length($i) > 2) {
				if (words != "") words = words "-"
				words = words $i
				count++
			}
		}
		print words
	}')

	if [[ -z "$slug" || "$slug" == "-" || "$slug" == "--" ]]; then
		slug="task-$(date +%s | tail -c 6)"
	fi

	# Ensure slug isn't too long
	slug="${slug:0:30}"

	echo "${commit_type}/${slug}"
}

# Main branch name generation function
generate_branch_name() {
	local branch_name=""

	# First, check if user specified a branch name
	branch_name="$(extract_user_branch_name)"
	if [[ -n "$branch_name" ]]; then
		debug_log "User specified branch name: $branch_name"
		# Validate it has a proper type prefix
		if validate_branch_type "$branch_name"; then
			echo "$branch_name"
			return 0
		else
			debug_log "User branch name missing valid type prefix, will add one"
			# Determine type and prepend it
			local commit_type
			commit_type="$(determine_type_heuristic)"
			echo "${commit_type}/${branch_name}"
			return 0
		fi
	fi

	# Try AI-generated branch name
	if branch_name="$(generate_ai_branch_name "$PROMPT")"; then
		echo "$branch_name"
		return 0
	fi

	# Fall back to heuristic generation
	debug_log "Falling back to heuristic branch name generation"
	generate_heuristic_branch_name
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
