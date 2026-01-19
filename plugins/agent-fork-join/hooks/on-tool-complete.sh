#!/usr/bin/env bash
# PostToolUse Hook - Tracks file writes for later commit
#
# This hook:
# 1. Detects when Write/Edit tools complete
# 2. Records the file path for the session-end commit
# 3. Does NOT commit immediately - the Stop hook handles that
#
# This ensures a single commit per agent session rather than per-file commits.

set -euo pipefail

# Debug logging
DEBUG_LOG="/tmp/fork-join-hook-debug.log"
debug_log() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] [POST_TOOL] $*" >>"${DEBUG_LOG}"
}

debug_log "=== PostToolUse hook started ==="

# Guard against recursive hook calls
if [[ "${FORK_JOIN_HOOK_CONTEXT:-}" == "1" ]]; then
	debug_log "Already in hook context, skipping to prevent recursion"
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
	source "${SCRIPT_DIR}/lib/common.sh"
else
	exit 0
fi

if [[ -f "${SCRIPT_DIR}/lib/git-utils.sh" ]]; then
	source "${SCRIPT_DIR}/lib/git-utils.sh"
else
	exit 0
fi

# Read the input from stdin or argument
RAW_INPUT="${1:-}"
if [[ -z "$RAW_INPUT" ]] && [[ ! -t 0 ]]; then
	RAW_INPUT="$(cat)"
fi

debug_log "Raw input: ${RAW_INPUT:0:200}..."

# Extract tool name and file path from JSON input
TOOL_NAME=""
FILE_PATH=""

if command -v jq >/dev/null 2>&1; then
	TOOL_NAME=$(echo "$RAW_INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null || echo "")
	# Try different JSON structures for file path
	FILE_PATH=$(echo "$RAW_INPUT" | jq -r '.tool_input.file_path // .file_path // .path // empty' 2>/dev/null || echo "")
fi

debug_log "Tool: $TOOL_NAME, File: $FILE_PATH"

# Only process Write and Edit tools
if [[ "$TOOL_NAME" != "Write" && "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "MultiEdit" ]]; then
	debug_log "Not a file write tool ($TOOL_NAME), skipping"
	exit 0
fi

# Ensure we have a file path
if [[ -z "$FILE_PATH" ]]; then
	debug_log "No file path found, skipping"
	exit 0
fi

# Ensure we're in a git repository
if ! git_is_repo; then
	debug_log "Not in a git repository, skipping"
	exit 0
fi

# Check if plugin should be active
if ! git_should_plugin_activate; then
	debug_log "Plugin not active (not GitHub or wrong branch), skipping"
	exit 0
fi

# Get current branch
current_branch="$(git_current_branch)"
debug_log "Current branch: $current_branch"

# Skip if on main branch (no session started)
if git_is_main_branch "$current_branch"; then
	debug_log "On main branch, skipping file tracking"
	exit 0
fi

# Check if the file exists and has changes
if [[ ! -f "$FILE_PATH" ]]; then
	debug_log "File does not exist: $FILE_PATH"
	exit 0
fi

# Check if file has changes (staged or unstaged)
if ! git status --porcelain "$FILE_PATH" 2>/dev/null | grep -q .; then
	debug_log "No changes to file: $FILE_PATH"
	exit 0
fi

debug_log "File has changes, recording for later commit: $FILE_PATH"

# Session state directory
STATE_DIR="${FORK_JOIN_STATE_DIR:-.fork-join}"

# Record the file for later commit (append to tracked files list)
mkdir -p "$STATE_DIR"
TRACKED_FILES="${STATE_DIR}/tracked_files.txt"

# Add file to tracked list if not already there
if ! grep -qxF "$FILE_PATH" "$TRACKED_FILES" 2>/dev/null; then
	echo "$FILE_PATH" >>"$TRACKED_FILES"
	debug_log "Added to tracked files: $FILE_PATH"
else
	debug_log "File already tracked: $FILE_PATH"
fi

# Output confirmation (not committing, just tracking)
echo "Tracked file change: $FILE_PATH (will commit on session end)"

debug_log "PostToolUse hook completed - file tracked for later commit"
