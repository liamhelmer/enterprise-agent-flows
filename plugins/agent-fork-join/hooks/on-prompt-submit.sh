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

debug_log "Raw input received: '${RAW_INPUT:0:200}...'"

# Extract the actual prompt from the JSON input
# The input is JSON with a "prompt" field containing the user's actual prompt
PROMPT=""
if command -v jq >/dev/null 2>&1; then
	# Try to extract the prompt field from JSON
	PROMPT=$(echo "$RAW_INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")

	# If jq returned empty or the raw input itself (parsing failed), try harder
	if [[ -z "$PROMPT" ]]; then
		debug_log "jq extraction returned empty, checking if input is valid JSON"
		# Check if input is valid JSON at all
		if echo "$RAW_INPUT" | jq -e . >/dev/null 2>&1; then
			debug_log "Input is valid JSON but has no prompt field"
			# It's valid JSON but no prompt field - this is an error condition
			PROMPT=""
		else
			debug_log "Input is not JSON, treating as raw prompt"
			# Not JSON, treat as raw prompt text
			PROMPT="$RAW_INPUT"
		fi
	fi
fi

# Fallback if jq not available: use grep/sed
if [[ -z "$PROMPT" ]] && ! command -v jq >/dev/null 2>&1; then
	debug_log "jq not available, using sed fallback"
	# Try to extract prompt using sed - this handles escaped quotes
	PROMPT=$(echo "$RAW_INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
	if [[ -z "$PROMPT" ]]; then
		# If sed failed and input doesn't look like JSON, use as-is
		if [[ "$RAW_INPUT" != "{"* ]]; then
			PROMPT="$RAW_INPUT"
		fi
	fi
fi

# Final check - if we still have no prompt, we cannot proceed
if [[ -z "$PROMPT" ]]; then
	debug_log "ERROR: Could not extract prompt from input"
	echo "ERROR: No prompt found in hook input" >&2
	exit 1
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

# Sanitize a string to be a valid git branch name
# - Removes newlines, control characters
# - Converts spaces and invalid chars to hyphens
# - Converts to lowercase
# - Removes consecutive hyphens
# - Limits length (truncates at word boundaries to avoid partial words)
sanitize_branch_name() {
	local input="$1"
	local max_length="${2:-50}"

	# Convert to single line, lowercase, remove control chars
	local sanitized
	sanitized=$(echo "$input" | tr '\n\r\t' ' ' | tr '[:upper:]' '[:lower:]')

	# Replace spaces and invalid git branch chars with hyphens
	# Valid git branch chars: alphanumeric, /, -, _, .
	sanitized=$(echo "$sanitized" | sed 's/[^a-z0-9/_.-]/-/g')

	# Remove consecutive hyphens
	sanitized=$(echo "$sanitized" | sed 's/--*/-/g')

	# Remove leading/trailing hyphens and dots
	sanitized=$(echo "$sanitized" | sed 's/^[-.]*//' | sed 's/[-.]*$//')

	# Truncate at word boundary (hyphen) to avoid partial words
	if [[ ${#sanitized} -gt $max_length ]]; then
		# First truncate to max_length
		sanitized="${sanitized:0:$max_length}"
		# Then find the last hyphen and truncate there to keep whole words
		if [[ "$sanitized" == *-* ]]; then
			# Remove the partial word after the last hyphen
			sanitized="${sanitized%-*}"
		fi
	fi

	# Remove trailing hyphen after truncation
	sanitized=$(echo "$sanitized" | sed 's/[-.]*$//')

	echo "$sanitized"
}

# Use Claude AI to generate a branch name following Angular conventions
generate_ai_branch_name() {
	local prompt_text="$1"
	local ai_branch=""

	debug_log "Using Claude AI to generate branch name..."

	# Sanitize the prompt for inclusion in AI request (first 500 chars, single line)
	local sanitized_prompt
	sanitized_prompt=$(echo "$prompt_text" | tr '\n\r' ' ' | head -c 500)

	# Create a prompt for Claude to generate the branch name
	local ai_prompt
	ai_prompt="Analyze this task and generate a git branch name.

VALID TYPES: feat, fix, refactor, perf, test, docs, build, ci

FORMAT: <type>/<short-description>
- lowercase only
- hyphens between words
- max 40 chars in description
- use complete words only (no truncated words)

TASK: ${sanitized_prompt}

OUTPUT ONLY THE BRANCH NAME (e.g., feat/add-user-auth):"

	# Call Claude CLI with speed optimizations
	export FORK_JOIN_HOOK_CONTEXT=1
	local raw_response=""
	raw_response=$(claude_fast_call "$ai_prompt" 10)
	unset FORK_JOIN_HOOK_CONTEXT

	debug_log "AI raw response: '${raw_response:0:100}...'"

	# Clean the response: remove newlines, extract branch name pattern
	# First, collapse to single line and trim whitespace
	ai_branch=$(echo "$raw_response" | tr '\n\r\t' ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

	# Extract just the branch name pattern (type/description)
	ai_branch=$(echo "$ai_branch" | grep -oE '(build|ci|docs|feat|fix|perf|refactor|test)/[a-z0-9-]+' | head -1)

	# Final sanitization
	if [[ -n "$ai_branch" ]]; then
		local branch_type branch_desc
		branch_type=$(echo "$ai_branch" | cut -d'/' -f1)
		branch_desc=$(echo "$ai_branch" | cut -d'/' -f2-)
		branch_desc=$(sanitize_branch_name "$branch_desc" 40)
		ai_branch="${branch_type}/${branch_desc}"
	fi

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

	# First, sanitize the prompt to a single line for processing
	local single_line_prompt
	single_line_prompt=$(echo "$PROMPT" | tr '\n\r\t' ' ' | head -c 200)

	# Extract key words from prompt for description
	local slug
	slug=$(echo "$single_line_prompt" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]/ /g' | awk '{
		# Skip common words and the type we detected
		skip["the"] = 1; skip["a"] = 1; skip["an"] = 1; skip["to"] = 1;
		skip["and"] = 1; skip["or"] = 1; skip["for"] = 1; skip["in"] = 1;
		skip["on"] = 1; skip["with"] = 1; skip["that"] = 1; skip["this"] = 1;
		skip["is"] = 1; skip["are"] = 1; skip["be"] = 1; skip["will"] = 1;
		skip["please"] = 1; skip["can"] = 1; skip["you"] = 1; skip["i"] = 1;
		skip["implement"] = 1; skip["add"] = 1; skip["create"] = 1;
		skip["fix"] = 1; skip["update"] = 1; skip["modify"] = 1;
		skip["task"] = 1; skip["using"] = 1; skip["use"] = 1;
		skip["tool"] = 1; skip["must"] = 1; skip["each"] = 1;
		words = ""
		count = 0
		for (i = 1; i <= NF && count < 4; i++) {
			if (!($i in skip) && length($i) > 2) {
				if (words != "") words = words "-"
				words = words $i
				count++
			}
		}
		print words
	}')

	# Sanitize the slug
	slug=$(sanitize_branch_name "$slug" 40)

	if [[ -z "$slug" || "$slug" == "-" ]]; then
		slug="task-$(date +%s | tail -c 6)"
	fi

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

# Use AI to analyze if PR description needs updating and what changes to make
analyze_pr_for_updates() {
	local current_body="$1"
	local new_prompt="$2"

	debug_log "Using Claude haiku to analyze PR description..."

	# Truncate inputs for AI (prevent context overflow)
	local sanitized_body
	sanitized_body=$(echo "$current_body" | head -c 2000)
	local sanitized_prompt
	sanitized_prompt=$(echo "$new_prompt" | tr '\n' ' ' | head -c 800)

	local ai_prompt="Analyze this PR description and determine if it needs updating based on the new prompt.

CURRENT PR DESCRIPTION:
${sanitized_body}

NEW PROMPT FROM USER:
${sanitized_prompt}

INSTRUCTIONS:
1. Compare the new prompt to what's already described in the PR
2. If the new prompt adds NEW functionality not covered in the Summary/Changes sections, output suggested updates
3. If the new prompt is just continuation of existing work, output 'NO_UPDATE_NEEDED'

OUTPUT FORMAT:
- If updates needed: Output ONLY the text to ADD to the 'Changes Made' section (bullet points starting with '- ')
- If no updates needed: Output exactly 'NO_UPDATE_NEEDED'

Be concise. Output nothing else."

	export FORK_JOIN_HOOK_CONTEXT=1
	local analysis=""
	analysis=$(claude_fast_call "$ai_prompt" 15)
	unset FORK_JOIN_HOOK_CONTEXT

	if [[ -n "$analysis" ]]; then
		debug_log "AI analysis result: ${analysis:0:100}..."
		echo "$analysis"
		return 0
	fi
	return 1
}

# Append a new prompt to an existing PR description
append_prompt_to_pr() {
	local pr_number="$1"
	local new_prompt="$2"

	debug_log "Appending prompt to PR #${pr_number}"

	# Get current PR body
	local current_body
	current_body="$(git_get_pr_body "$pr_number")"

	if [[ -z "$current_body" ]]; then
		debug_log "Could not retrieve PR body"
		return 1
	fi

	# Generate timestamp for this prompt
	local prompt_timestamp
	prompt_timestamp=$(format_timestamp)

	# Analyze if PR description needs content updates (not just appending prompt)
	local ai_analysis=""
	ai_analysis=$(analyze_pr_for_updates "$current_body" "$new_prompt") || true
	debug_log "AI analysis: ${ai_analysis:0:100}..."

	# Create the new prompt accordion section
	local new_prompt_section="
<details>
<summary>📝 Prompt - ${prompt_timestamp}</summary>

\`\`\`
${new_prompt}
\`\`\`

</details>"

	# Build the updated body
	local updated_body="$current_body"

	# If AI suggested updates to the description content, we could integrate them
	# For now, we log it but primarily focus on appending the prompt
	if [[ -n "$ai_analysis" && "$ai_analysis" != "NO_UPDATE_NEEDED" && "$ai_analysis" != *"NO_UPDATE"* ]]; then
		debug_log "AI suggests description updates: ${ai_analysis:0:200}"
		# Note: We could modify the PR body here to add new bullet points
		# For safety, we just log it and append the prompt
	fi

	# Find where to append the new prompt section
	# Strategy: Look for existing "## Prompt History" section or append at end
	if [[ "$updated_body" == *"## Prompt History"* ]]; then
		# Append the new prompt section after the existing prompt history
		# Find the last </details> in the Prompt History section and append after it
		updated_body="${updated_body}
${new_prompt_section}"
	else
		# No prompt history section exists - create one
		# Append it at the very end
		updated_body="${updated_body}

---

## Prompt History
${new_prompt_section}"
	fi

	# Update the PR
	if git_update_pr_body "$pr_number" "$updated_body"; then
		debug_log "Successfully updated PR #${pr_number} body"
		log_info "Appended new prompt to PR #${pr_number}"
		return 0
	else
		debug_log "Failed to update PR body"
		return 1
	fi
}

main() {
	debug_log "main() called"
	log_info "UserPromptSubmit hook triggered"

	debug_log "PROMPT value: '${PROMPT:0:100}...'" # First 100 chars

	# Ensure we're in a git repository first
	if ! git_is_repo; then
		debug_log "Not in a git repository, skipping"
		log_debug "Not in a git repository, skipping"
		exit 0
	fi
	debug_log "Confirmed: in a git repository"

	# Check if current JIRA ticket is marked as done - if so, clean up and prompt for next ticket
	local current_ticket=""
	if current_ticket=$(jira_get_current_ticket 2>/dev/null); then
		debug_log "Found current JIRA ticket: $current_ticket"

		# Sync with JIRA to get latest status
		bd jira sync --pull 2>/dev/null || true

		if jira_is_ticket_done "$current_ticket"; then
			debug_log "Current ticket $current_ticket is done, cleaning up"
			log_info "Current JIRA ticket $current_ticket is marked as done"

			# Clean up the current-ticket symlink
			jira_clear_current_ticket

			# Signal to Claude to run /jira:work
			echo ""
			echo "=== JIRA Ticket Completed ==="
			echo ""
			echo "The current JIRA ticket ($current_ticket) has been marked as Done."
			echo "The ticket tracking has been cleared."
			echo ""
			echo "JIRA_TICKET_DONE=true"
			echo "JIRA_COMPLETED_TICKET=$current_ticket"
			echo ""
			echo "The Claude agent should now run /jira:work to select the next ticket."
			echo ""
		fi
	fi

	# Check if this is a GitHub repository and we're on an appropriate branch
	if ! git_should_plugin_activate; then
		debug_log "Plugin should not activate (not GitHub repo or not on default/plugin branch)"
		log_debug "Plugin not activating - not a GitHub repo or not on default/plugin branch"
		exit 0
	fi
	debug_log "Plugin activation check passed"

	# Check if prompt will make changes
	if ! prompt_will_make_changes; then
		debug_log "Prompt does NOT appear to make changes, skipping"
		log_debug "Prompt does not appear to make changes, skipping"
		exit 0
	fi

	debug_log "Prompt WILL make changes"
	log_info "Detected change-making prompt"

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

		# Check if a PR exists for this branch
		local existing_pr
		existing_pr="$(git_get_pr_number "$current_branch")"

		if [[ -n "$existing_pr" ]]; then
			debug_log "Found existing PR #${existing_pr} for branch $current_branch"
			log_info "Existing PR #${existing_pr} found, analyzing for updates..."

			# Append the new prompt to the PR description
			append_prompt_to_pr "$existing_pr" "$PROMPT"

			echo "Updated PR #${existing_pr} with new prompt on branch: $current_branch"
		else
			debug_log "No existing PR for branch $current_branch"
			echo "Already on feature branch: $current_branch"
		fi

		# Store the new prompt in session state for this continuation
		if [[ -f "${STATE_DIR}/current_session" ]]; then
			local session_id
			session_id="$(cat "${STATE_DIR}/current_session")"
			local session_file="${STATE_DIR}/${session_id}.json"

			if [[ -f "$session_file" ]]; then
				# Add this prompt to the prompts array with timestamp
				local timestamp
				timestamp=$(format_timestamp)
				jq --arg prompt "$PROMPT" --arg ts "$timestamp" \
					'.prompts = (.prompts // []) + [{"prompt": $prompt, "timestamp": $ts}]' \
					"$session_file" >"${session_file}.tmp" && mv "${session_file}.tmp" "$session_file"
				debug_log "Added prompt to session state"
			fi
		fi
	fi

	debug_log "Hook completed successfully"
	log_info "Fork-join hook completed"
}

debug_log "About to call main()"
main "$@"
debug_log "main() returned"
