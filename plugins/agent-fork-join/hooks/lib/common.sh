#!/usr/bin/env bash
# Common utility functions for fork-join hooks

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log levels
LOG_LEVEL="${FORK_JOIN_LOG_LEVEL:-INFO}"

# Logging functions
log_debug() {
	if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
		echo -e "${BLUE}[DEBUG]${NC} $*" >&2
	fi
}

log_info() {
	if [[ "$LOG_LEVEL" == "DEBUG" || "$LOG_LEVEL" == "INFO" ]]; then
		echo -e "${GREEN}[INFO]${NC} $*" >&2
	fi
}

log_warn() {
	if [[ "$LOG_LEVEL" != "ERROR" ]]; then
		echo -e "${YELLOW}[WARN]${NC} $*" >&2
	fi
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if a command exists
command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# Ensure required commands are available
require_commands() {
	local missing=()
	for cmd in "$@"; do
		if ! command_exists "$cmd"; then
			missing+=("$cmd")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		log_error "Missing required commands: ${missing[*]}"
		return 1
	fi
}

# Generate a short unique ID
generate_short_id() {
	if command_exists uuidgen; then
		uuidgen | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]'
	else
		head -c 8 /dev/urandom | xxd -p | head -c 8
	fi
}

# Safe JSON string escaping
json_escape() {
	printf '%s' "$1" | jq -Rs .
}

# Read JSON value from string
json_get() {
	local json="$1"
	local key="$2"
	echo "$json" | jq -r ".$key // empty"
}

# Check if running in CI environment
is_ci() {
	[[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" || -n "${JENKINS_URL:-}" ]]
}

# Cleanup function for traps
cleanup() {
	local exit_code=$?
	# Add cleanup logic here
	exit $exit_code
}

# Set up trap for cleanup
setup_cleanup_trap() {
	trap cleanup EXIT INT TERM
}

# ==========================================
# JIRA Config Cache Functions (Fast Path)
# ==========================================

# Cache file locations (no secrets stored - JIRA_API_TOKEN always from env)
JIRA_CONFIG_CACHE=".jira/config.cache"
JIRA_TICKET_CACHE=".jira/current-ticket.cache"

# Get cached JIRA config value (fast - no bd calls)
# Usage: jira_get_cached_config "JIRA_URL"
# Returns: cached value or empty string
jira_get_cached_config() {
	local key="$1"
	if [[ -f "$JIRA_CONFIG_CACHE" ]]; then
		local value
		value=$(grep "^${key}=" "$JIRA_CONFIG_CACHE" 2>/dev/null | head -1 | cut -d'"' -f2)
		echo "$value"
	fi
}

# Get cached ticket info (fast - no bd calls)
# Usage: jira_get_cached_ticket "JIRA_KEY"
# Returns: cached value or empty string
jira_get_cached_ticket() {
	local key="$1"
	if [[ -f "$JIRA_TICKET_CACHE" ]]; then
		local value
		value=$(grep "^${key}=" "$JIRA_TICKET_CACHE" 2>/dev/null | head -1 | cut -d'"' -f2)
		echo "$value"
	fi
}

# Update a value in the ticket cache
# Usage: jira_update_ticket_cache "ISSUE_STATUS" "in_progress"
jira_update_ticket_cache() {
	local key="$1"
	local value="$2"
	if [[ -f "$JIRA_TICKET_CACHE" ]]; then
		sed -i.bak "s/^${key}=.*/${key}=\"${value}\"/" "$JIRA_TICKET_CACHE" 2>/dev/null || true
		rm -f "${JIRA_TICKET_CACHE}.bak" 2>/dev/null || true
	fi
}

# Check if ticket cache exists and is valid
jira_has_ticket_cache() {
	[[ -f "$JIRA_TICKET_CACHE" ]]
}

# Check if config cache exists and is valid (less than 1 hour old)
jira_has_valid_config_cache() {
	if [[ ! -f "$JIRA_CONFIG_CACHE" ]]; then
		return 1
	fi
	local cache_age
	cache_age=$(($(date +%s) - $(stat -f %m "$JIRA_CONFIG_CACHE" 2>/dev/null || stat -c %Y "$JIRA_CONFIG_CACHE" 2>/dev/null || echo 0)))
	[[ $cache_age -lt 3600 ]] # 1 hour
}

# ==========================================
# Beads Issue Tracking Functions
# ==========================================

# Get current beads issue ID from .beads/current-issue
# Returns: beads ID (e.g., "bd-100") or empty string if not set
beads_get_current_issue() {
	local beads_dir=".beads"
	local current_issue_file="${beads_dir}/current-issue"

	if [[ ! -f "$current_issue_file" ]]; then
		return 1
	fi

	local issue_id
	issue_id=$(cat "$current_issue_file" 2>/dev/null | tr -d '[:space:]')

	if [[ -n "$issue_id" ]]; then
		echo "$issue_id"
		return 0
	fi

	return 1
}

# Get beads issue field
# Usage: beads_get_issue_field "bd-100" "title"
# Available fields: id, title, status, priority, external_ref, assignee, jira_key
beads_get_issue_field() {
	local issue_id="$1"
	local field="$2"

	if ! command -v bd >/dev/null 2>&1; then
		return 1
	fi

	# Use bd show with JSON output
	local value
	value=$(bd show "$issue_id" --json 2>/dev/null | jq -r ".$field // empty" 2>/dev/null)

	if [[ -n "$value" && "$value" != "null" ]]; then
		echo "$value"
		return 0
	fi

	return 1
}

# Get JIRA key for a beads issue (from external_ref URL)
# Usage: beads_get_jira_key "bd-100"
# Returns: JIRA key (e.g., "PGF-123") or empty string
beads_get_jira_key() {
	local issue_id="$1"

	if ! command -v bd >/dev/null 2>&1; then
		return 1
	fi

	# Get external_ref which contains JIRA URL like https://badal.atlassian.net/browse/PGF-123
	local external_ref
	external_ref=$(beads_get_issue_field "$issue_id" "external_ref")

	if [[ -n "$external_ref" && "$external_ref" == *"/browse/"* ]]; then
		# Extract JIRA key from URL
		local jira_key
		jira_key=$(echo "$external_ref" | sed 's|.*/browse/||')
		echo "$jira_key"
		return 0
	fi

	return 1
}

# Get JIRA URL for a beads issue
# Usage: beads_get_jira_url "bd-100"
beads_get_jira_url() {
	local issue_id="$1"
	beads_get_issue_field "$issue_id" "external_ref"
}

# Get JIRA URL base from beads config
jira_get_url() {
	if command -v bd >/dev/null 2>&1; then
		bd config get jira.url 2>/dev/null || echo ""
	else
		echo ""
	fi
}

# Get JIRA project from beads config
jira_get_project() {
	if command -v bd >/dev/null 2>&1; then
		bd config get jira.project 2>/dev/null || echo ""
	else
		echo ""
	fi
}

# Add a comment to a beads issue and sync to JIRA
# Usage: beads_add_comment "bd-100" "Comment text"
beads_add_comment() {
	local issue_id="$1"
	local comment="$2"

	if ! command -v bd >/dev/null 2>&1; then
		log_debug "beads CLI not available, cannot add comment"
		return 1
	fi

	bd comments add "$issue_id" --body "$comment" 2>/dev/null || {
		log_debug "Could not add comment to beads issue $issue_id"
		return 1
	}

	# Sync to JIRA to push the comment
	bd jira sync --push 2>/dev/null || {
		log_debug "Could not sync comment to JIRA"
		# Don't fail - local comment was added successfully
	}
}

# Update beads issue status and sync to JIRA
# Usage: beads_update_status "bd-100" "closed"
# Valid statuses: open, in_progress, blocked, deferred, closed
beads_update_status() {
	local issue_id="$1"
	local status="$2"

	if ! command -v bd >/dev/null 2>&1; then
		log_debug "beads CLI not available, cannot update status"
		return 1
	fi

	bd update "$issue_id" --status="$status" 2>/dev/null || {
		log_debug "Could not update beads issue $issue_id status"
		return 1
	}

	# Sync to JIRA to push the status change
	bd jira sync --push 2>/dev/null || {
		log_debug "Could not sync status to JIRA"
		# Don't fail - local status was updated successfully
	}
}

# Check if beads issue is closed
# Usage: beads_is_issue_closed "bd-100"
# Returns: 0 if closed, 1 otherwise
beads_is_issue_closed() {
	local issue_id="$1"

	if ! command -v bd >/dev/null 2>&1; then
		log_debug "beads CLI not available, cannot check status"
		return 1
	fi

	local status
	status=$(beads_get_issue_field "$issue_id" "status")

	case "$status" in
	"closed")
		log_debug "Issue $issue_id is closed"
		return 0
		;;
	*)
		log_debug "Issue $issue_id status is: $status (not closed)"
		return 1
		;;
	esac
}

# Set current beads issue
# Usage: beads_set_current_issue "bd-100"
beads_set_current_issue() {
	local issue_id="$1"
	local beads_dir=".beads"

	# Verify the issue exists
	if ! bd show "$issue_id" >/dev/null 2>&1; then
		log_debug "Issue $issue_id not found in beads"
		return 1
	fi

	# Create .beads directory if it doesn't exist (should already exist)
	mkdir -p "$beads_dir"

	# Write the issue ID to current-issue file
	echo "$issue_id" >"${beads_dir}/current-issue"
	log_debug "Set current issue to $issue_id"
	return 0
}

# Clear current beads issue
beads_clear_current_issue() {
	local beads_dir=".beads"
	local current_issue_file="${beads_dir}/current-issue"

	if [[ -f "$current_issue_file" ]]; then
		rm -f "$current_issue_file"
		log_debug "Cleared current beads issue"
	fi
}

# Map JIRA status to beads status
# Usage: map_jira_to_beads_status "In Progress"
# Returns: beads status (open, in_progress, blocked, deferred, closed)
map_jira_to_beads_status() {
	local jira_status="$1"
	local status_lower
	status_lower=$(echo "$jira_status" | tr '[:upper:]' '[:lower:]')

	case "$status_lower" in
	"to do" | "todo" | "open" | "backlog" | "new")
		echo "open"
		;;
	"in progress" | "in development" | "in review" | "review")
		echo "in_progress"
		;;
	"blocked" | "on hold")
		echo "blocked"
		;;
	"deferred" | "postponed" | "later")
		echo "deferred"
		;;
	"done" | "closed" | "resolved" | "complete" | "completed" | "won't do" | "won't fix")
		echo "closed"
		;;
	*)
		echo "open"
		;;
	esac
}

# Map beads status to JIRA status
# Usage: map_beads_to_jira_status "in_progress"
# Returns: JIRA-friendly status name
map_beads_to_jira_status() {
	local beads_status="$1"

	case "$beads_status" in
	"open")
		echo "To Do"
		;;
	"in_progress")
		echo "In Progress"
		;;
	"blocked")
		echo "Blocked"
		;;
	"deferred")
		echo "Deferred"
		;;
	"closed")
		echo "Done"
		;;
	*)
		echo "To Do"
		;;
	esac
}

# Find beads issue by JIRA key
# Usage: beads_find_by_jira_key "PGF-123"
# Returns: beads ID (e.g., "bd-100") or empty string
# Note: Uses jq --arg to safely inject the JIRA key and --first to stop at first match
beads_find_by_jira_key() {
	local jira_key="$1"

	if ! command -v bd >/dev/null 2>&1; then
		return 1
	fi

	# Use jq --arg for safe variable injection and --first for efficiency
	# The select filter runs on the stream, stopping at first match
	local beads_id
	beads_id=$(bd list --json 2>/dev/null | jq -r --arg key "$jira_key" 'first(.[] | select(.external_ref != null and (.external_ref | contains($key))) | .id) // empty' 2>/dev/null)

	if [[ -n "$beads_id" && "$beads_id" != "null" ]]; then
		echo "$beads_id"
		return 0
	fi

	return 1
}

# ==========================================
# Legacy JIRA functions (for backwards compatibility)
# These map to the new beads functions
# ==========================================

# Get current JIRA ticket - now uses beads
jira_get_current_ticket() {
	local issue_id
	if issue_id=$(beads_get_current_issue); then
		beads_get_jira_key "$issue_id"
	else
		return 1
	fi
}

# Check if JIRA ticket is done - now uses beads
jira_is_ticket_done() {
	local issue_id
	if issue_id=$(beads_get_current_issue); then
		beads_is_issue_closed "$issue_id"
	else
		return 1
	fi
}

# Clear current ticket - now uses beads
jira_clear_current_ticket() {
	beads_clear_current_issue
}

# ==========================================
# Claude AI Functions
# ==========================================

# Non-interactive Claude call with speed optimizations
# Usage: claude_fast_call "prompt" [timeout_seconds]
# Returns: AI response on stdout, or empty string on failure
claude_fast_call() {
	local prompt="$1"
	local timeout_seconds="${2:-15}"

	# Check if claude CLI is available
	if ! command -v claude >/dev/null 2>&1; then
		log_debug "Claude CLI not available"
		return 1
	fi

	# Build the claude command with all speed optimization flags
	local claude_cmd="claude -p --model haiku --no-chrome --no-session-persistence"
	claude_cmd+=" --setting-sources '' --disable-slash-commands"
	claude_cmd+=" --strict-mcp-config --mcp-config ''"

	local result=""

	# Use timeout if available (Linux has timeout, macOS has gtimeout via coreutils)
	if command -v timeout >/dev/null 2>&1; then
		result=$(echo "$prompt" | timeout "$timeout_seconds" bash -c "$claude_cmd -p -" 2>/dev/null) || true
	elif command -v gtimeout >/dev/null 2>&1; then
		result=$(echo "$prompt" | gtimeout "$timeout_seconds" bash -c "$claude_cmd -p -" 2>/dev/null) || true
	else
		# Fallback: use background process with sleep-based timeout
		local tmp_output
		tmp_output=$(mktemp)
		(echo "$prompt" | bash -c "$claude_cmd -p -" >"$tmp_output" 2>/dev/null) &
		local pid=$!
		local waited=0
		while kill -0 $pid 2>/dev/null && [[ $waited -lt $timeout_seconds ]]; do
			sleep 1
			((waited++))
		done
		if kill -0 $pid 2>/dev/null; then
			kill $pid 2>/dev/null || true
			wait $pid 2>/dev/null || true
		fi
		if [[ -f "$tmp_output" ]]; then
			result=$(cat "$tmp_output")
			rm -f "$tmp_output"
		fi
	fi

	echo "$result"
}
