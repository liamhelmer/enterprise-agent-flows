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
