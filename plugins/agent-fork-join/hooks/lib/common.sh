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
# JIRA Integration Functions
# ==========================================

# Get current JIRA ticket ID from .jira/current-ticket symlink
# Returns: ticket ID (e.g., "PGF-123") or empty string if not set
jira_get_current_ticket() {
	local jira_dir=".jira"
	local current_ticket_link="${jira_dir}/current-ticket"

	if [[ ! -L "$current_ticket_link" && ! -f "$current_ticket_link" ]]; then
		return 1
	fi

	# Get the ticket ID (filename the symlink points to)
	local ticket_id
	if [[ -L "$current_ticket_link" ]]; then
		ticket_id=$(readlink "$current_ticket_link" | xargs basename)
	else
		ticket_id=$(cat "$current_ticket_link" 2>/dev/null | grep "^ticket_id=" | cut -d= -f2)
	fi

	if [[ -n "$ticket_id" ]]; then
		echo "$ticket_id"
		return 0
	fi

	return 1
}

# Get JIRA ticket metadata
# Usage: jira_get_ticket_field "PGF-123" "summary"
# Available fields: ticket_id, started_at, summary, url
jira_get_ticket_field() {
	local ticket_id="$1"
	local field="$2"
	local jira_dir=".jira"
	local ticket_file="${jira_dir}/${ticket_id}"

	if [[ ! -f "$ticket_file" ]]; then
		return 1
	fi

	local value
	value=$(grep "^${field}=" "$ticket_file" 2>/dev/null | cut -d= -f2-)
	if [[ -n "$value" ]]; then
		echo "$value"
		return 0
	fi

	return 1
}

# Get JIRA URL from beads config
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

# Add a comment to a JIRA issue via beads
# Usage: jira_add_comment "PGF-123" "Comment text"
jira_add_comment() {
	local ticket_id="$1"
	local comment="$2"

	if ! command -v bd >/dev/null 2>&1; then
		log_debug "beads CLI not available, cannot add JIRA comment"
		return 1
	fi

	# Use beads to add comment
	# Note: bd comments add expects the beads issue ID format
	# We need to find the local beads issue that corresponds to this JIRA ticket
	local beads_id
	beads_id=$(bd list --format=json 2>/dev/null | jq -r ".[] | select(.jira_key == \"$ticket_id\") | .id" 2>/dev/null || echo "")

	if [[ -n "$beads_id" ]]; then
		bd comments add "$beads_id" --body "$comment" 2>/dev/null && return 0
	fi

	# Fallback: try using the ticket ID directly if beads supports it
	bd comments add "$ticket_id" --body "$comment" 2>/dev/null || {
		log_debug "Could not add comment to JIRA ticket $ticket_id via beads"
		return 1
	}
}

# Update JIRA issue status via beads
# Usage: jira_update_status "PGF-123" "done"
jira_update_status() {
	local ticket_id="$1"
	local status="$2"

	if ! command -v bd >/dev/null 2>&1; then
		log_debug "beads CLI not available, cannot update JIRA status"
		return 1
	fi

	# Find beads issue ID
	local beads_id
	beads_id=$(bd list --format=json 2>/dev/null | jq -r ".[] | select(.jira_key == \"$ticket_id\") | .id" 2>/dev/null || echo "")

	if [[ -n "$beads_id" ]]; then
		bd update "$beads_id" --status="$status" 2>/dev/null && return 0
	fi

	# Fallback: try using the ticket ID directly
	bd update "$ticket_id" --status="$status" 2>/dev/null || {
		log_debug "Could not update JIRA ticket $ticket_id status via beads"
		return 1
	}
}

# Check if JIRA ticket status is "done" (or similar closed status)
# Usage: jira_is_ticket_done "PGF-123"
# Returns: 0 if ticket is done, 1 otherwise
jira_is_ticket_done() {
	local ticket_id="$1"

	if ! command -v bd >/dev/null 2>&1; then
		log_debug "beads CLI not available, cannot check JIRA status"
		return 1
	fi

	# Get the ticket status from beads
	local status
	status=$(bd list --format=json 2>/dev/null | jq -r ".[] | select(.jira_key == \"$ticket_id\") | .status" 2>/dev/null || echo "")

	# Check for various "done" status values (case-insensitive)
	local status_lower
	status_lower=$(echo "$status" | tr '[:upper:]' '[:lower:]')

	case "$status_lower" in
	"done" | "closed" | "resolved" | "complete" | "completed")
		log_debug "Ticket $ticket_id has done status: $status"
		return 0
		;;
	*)
		log_debug "Ticket $ticket_id status is: $status (not done)"
		return 1
		;;
	esac
}

# Clean up .jira/current-ticket symlink
jira_clear_current_ticket() {
	local jira_dir=".jira"
	local current_ticket_link="${jira_dir}/current-ticket"

	if [[ -L "$current_ticket_link" || -f "$current_ticket_link" ]]; then
		rm -f "$current_ticket_link"
		log_debug "Cleared current JIRA ticket"
	fi
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
