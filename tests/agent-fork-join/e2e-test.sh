#!/usr/bin/env bash
#
# End-to-End Test for agent-fork-join plugin
#
# This script:
# 1) Creates a unique test repository using gh in the user's org
# 2) Initializes with CLAUDE.md, AGENTS.md, and the agent-fork-join plugin
# 3) Creates a prompt requiring 5+ concurrent agents
# 4) Spawns a Claude instance to run the prompt
# 5) Verifies branch creation with 5+ commits and a PR
# 6) Optional --clean flag to clean up everything
#
# Usage:
#   ./e2e-test.sh [--clean] [--org ORG_NAME] [--timeout SECONDS]
#
# Requirements:
#   - gh CLI authenticated
#   - claude CLI installed
#   - cargo (for daemon build)
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../plugins/agent-fork-join" && pwd)"

# Configuration
DEFAULT_ORG="liamhelmer"
DEFAULT_TIMEOUT=300   # 5 minutes (fail if exceeded)
DEFAULT_MODEL="haiku" # Use haiku for speed and cost
TEST_REPO_PREFIX="fork-join-test"
LOG_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Cross-platform timeout function (macOS doesn't have timeout command)
run_with_timeout() {
	local timeout_secs="$1"
	shift
	local cmd=("$@")

	# Check if GNU timeout exists (Linux or macOS with coreutils)
	if command -v timeout >/dev/null 2>&1; then
		timeout "${timeout_secs}" "${cmd[@]}"
		return $?
	elif command -v gtimeout >/dev/null 2>&1; then
		# macOS with Homebrew coreutils
		gtimeout "${timeout_secs}" "${cmd[@]}"
		return $?
	else
		# Pure bash implementation for macOS
		"${cmd[@]}" &
		local cmd_pid=$!

		# Background watcher that kills the process after timeout
		(
			sleep "${timeout_secs}"
			kill -TERM "${cmd_pid}" 2>/dev/null
			sleep 2
			kill -KILL "${cmd_pid}" 2>/dev/null
		) &
		local watcher_pid=$!

		# Wait for the command
		wait "${cmd_pid}" 2>/dev/null
		local exit_code=$?

		# Kill the watcher if command finished before timeout
		kill "${watcher_pid}" 2>/dev/null
		wait "${watcher_pid}" 2>/dev/null

		# Check if the process was killed by timeout (exit code 143 = SIGTERM, 137 = SIGKILL)
		if [[ $exit_code -eq 143 || $exit_code -eq 137 ]]; then
			return 124 # Standard timeout exit code
		fi

		return $exit_code
	fi
}

# Parse arguments
CLEAN_UP=false
ORG_NAME="${DEFAULT_ORG}"
TIMEOUT="${DEFAULT_TIMEOUT}"
MODEL="${DEFAULT_MODEL}"
REPO_NAME=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
	case $1 in
	--clean)
		CLEAN_UP=true
		shift
		;;
	--org)
		ORG_NAME="$2"
		shift 2
		;;
	--timeout)
		TIMEOUT="$2"
		shift 2
		;;
	--repo)
		REPO_NAME="$2"
		shift 2
		;;
	--model)
		MODEL="$2"
		shift 2
		;;
	--verbose | -v)
		VERBOSE=true
		shift
		;;
	--help | -h)
		cat <<EOF
Usage: $0 [OPTIONS]

End-to-end test for the agent-fork-join plugin.

Options:
  --clean           Clean up the test repository after test completes
  --org ORG         GitHub organization/user (default: ${DEFAULT_ORG})
  --timeout SECS    Timeout in seconds (default: ${DEFAULT_TIMEOUT}, test fails if exceeded)
  --model MODEL     Claude model to use (default: ${DEFAULT_MODEL})
  --repo NAME       Use specific repo name instead of generated one
  --verbose, -v     Verbose output
  --help, -h        Show this help message

Examples:
  $0                    # Run test, keep repo
  $0 --clean            # Run test, delete repo after
  $0 --model sonnet     # Use sonnet model
  $0 --org myorg        # Run test in different org
EOF
		exit 0
		;;
	*)
		log_error "Unknown option: $1"
		exit 1
		;;
	esac
done

# Generate unique repo name if not provided
if [[ -z "${REPO_NAME}" ]]; then
	REPO_NAME="${TEST_REPO_PREFIX}-${TIMESTAMP}"
fi

FULL_REPO="${ORG_NAME}/${REPO_NAME}"
TEST_DIR=""

# Cleanup function
cleanup() {
	local exit_code=$?

	log_info "Cleaning up..."

	# Stop any running daemon
	if [[ -n "${DAEMON_PID:-}" ]] && kill -0 "${DAEMON_PID}" 2>/dev/null; then
		kill "${DAEMON_PID}" 2>/dev/null || true
	fi

	# Remove local test directory
	if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
		rm -rf "${TEST_DIR}"
	fi

	# Delete remote repo if --clean was specified
	if [[ "${CLEAN_UP}" == "true" && -n "${REPO_NAME}" ]]; then
		log_info "Deleting remote repository ${FULL_REPO}..."
		gh repo delete "${FULL_REPO}" --yes 2>/dev/null || true
	fi

	exit $exit_code
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
	log_info "Checking prerequisites..."

	local missing=()

	command -v gh >/dev/null 2>&1 || missing+=("gh")
	command -v claude >/dev/null 2>&1 || missing+=("claude")
	command -v git >/dev/null 2>&1 || missing+=("git")
	command -v cargo >/dev/null 2>&1 || missing+=("cargo")
	command -v jq >/dev/null 2>&1 || missing+=("jq")

	if [[ ${#missing[@]} -gt 0 ]]; then
		log_error "Missing required tools: ${missing[*]}"
		exit 1
	fi

	# Check gh auth
	if ! gh auth status >/dev/null 2>&1; then
		log_error "gh CLI not authenticated. Run: gh auth login"
		exit 1
	fi

	# Check if plugin daemon is built
	if [[ ! -f "${PLUGIN_ROOT}/daemon/target/release/merge-daemon" ]]; then
		log_warn "Merge daemon not built. Building now..."
		(cd "${PLUGIN_ROOT}/daemon" && cargo build --release)
	fi

	log_success "All prerequisites satisfied"
}

# Create test repository
create_test_repo() {
	log_info "Creating test repository: ${FULL_REPO}"

	# Create the repo on GitHub
	gh repo create "${FULL_REPO}" \
		--public \
		--description "E2E test repository for agent-fork-join plugin" \
		--clone=false

	log_success "Created remote repository: ${FULL_REPO}"

	# Create local directory and initialize
	TEST_DIR="$(mktemp -d)"
	cd "${TEST_DIR}"

	git init
	git remote add origin "https://github.com/${FULL_REPO}.git"

	# Create initial files
	create_claude_md
	create_agents_md
	create_package_json
	setup_plugin

	# Initial commit
	git add .
	git commit -m "Initial commit: Set up test repository with agent-fork-join plugin"
	git branch -M main
	git push -u origin main

	log_success "Repository initialized and pushed"
}

# Create CLAUDE.md with fork-join plugin configuration
create_claude_md() {
	cat >CLAUDE.md <<'EOF'
# Test Project - Agent Fork-Join E2E Test

This is a test project for validating the agent-fork-join plugin.

## IMPORTANT: E2E Test Requirements

This project tests the agent-fork-join plugin. The following MUST be true:

1. **Branch creation is automatic**: The plugin's UserPromptSubmit hook MUST automatically
   create and push a feature branch when work begins. You do NOT need to create branches manually.

2. **Commits are automatic**: The plugin's AgentComplete hook MUST automatically commit
   changes when agents complete their work. You do NOT need to commit manually.

3. **PR creation is automatic**: The plugin MUST create the PR automatically.
   You do NOT need to create a PR manually.

Just focus on creating the requested files. The plugin handles all git operations.

## Project Structure

This project will be built by multiple concurrent agents, each creating a separate module.

## Plugin Configuration

The agent-fork-join plugin is configured with:
- Max concurrent agents: 8
- Merge strategy: rebase
- Branch naming: Angular commit types (feat/, fix/, refactor/, etc.)
- Agent branch prefix: agent/

## Development Rules

1. Each agent creates files in its assigned directory only
2. All code must include a file header comment
3. No agent should modify another agent's files
4. Tests should be created alongside implementation files

## Agent Assignment

When spawning agents for this project:
- Agent 1: Creates `/src/auth/` module (authentication)
- Agent 2: Creates `/src/api/` module (API endpoints)
- Agent 3: Creates `/src/db/` module (database layer)
- Agent 4: Creates `/src/utils/` module (utility functions)
- Agent 5: Creates `/src/config/` module (configuration management)
EOF
}

# Create AGENTS.md with agent definitions
create_agents_md() {
	cat >AGENTS.md <<'EOF'
# Agent Definitions

## Concurrent Agents for Module Development

This project uses 5 specialized agents working in parallel to build different modules.

### Agent 1: AuthAgent
- **Role**: Authentication module developer
- **Directory**: `/src/auth/`
- **Files to create**:
  - `index.ts` - Main authentication exports
  - `jwt.ts` - JWT token handling
  - `middleware.ts` - Auth middleware

### Agent 2: APIAgent
- **Role**: API endpoint developer
- **Directory**: `/src/api/`
- **Files to create**:
  - `index.ts` - API router setup
  - `users.ts` - User endpoints
  - `health.ts` - Health check endpoint

### Agent 3: DBAgent
- **Role**: Database layer developer
- **Directory**: `/src/db/`
- **Files to create**:
  - `index.ts` - Database connection
  - `models.ts` - Data models
  - `migrations.ts` - Migration helpers

### Agent 4: UtilsAgent
- **Role**: Utility functions developer
- **Directory**: `/src/utils/`
- **Files to create**:
  - `index.ts` - Utility exports
  - `logger.ts` - Logging utility
  - `validators.ts` - Input validators

### Agent 5: ConfigAgent
- **Role**: Configuration management developer
- **Directory**: `/src/config/`
- **Files to create**:
  - `index.ts` - Config exports
  - `env.ts` - Environment handling
  - `constants.ts` - Application constants

## Coordination

All agents should:
1. Work only in their assigned directories
2. Create all listed files
3. Include proper TypeScript types
4. Add file header comments with agent name
EOF
}

# Create package.json for validation
create_package_json() {
	cat >package.json <<'EOF'
{
  "name": "fork-join-test-project",
  "version": "1.0.0",
  "description": "E2E test project for agent-fork-join plugin",
  "main": "src/index.ts",
  "scripts": {
    "test": "echo 'Tests passed'",
    "lint": "echo 'Lint passed'",
    "typecheck": "echo 'Typecheck passed'"
  },
  "devDependencies": {}
}
EOF
}

# Set up the agent-fork-join plugin using claude plugin commands
# This simulates installing from the marketplace using a local path
setup_plugin() {
	log_info "Installing plugin using claude plugin commands..."

	# Get the path to the plugins directory (parent of the specific plugin)
	local plugins_dir
	plugins_dir="$(dirname "${PLUGIN_ROOT}")"

	# Remove existing marketplace to ensure fresh plugin files (avoid caching issues)
	log_info "Removing existing marketplace if present..."
	claude plugin marketplace remove enterprise-agent-flows 2>&1 || true

	# Add the plugins directory as a local marketplace
	log_info "Adding local marketplace: ${plugins_dir}"
	if ! claude plugin marketplace add "${plugins_dir}" 2>&1; then
		log_warn "Failed to add marketplace, trying to continue..."
	fi

	# Install the plugin from the marketplace with project scope
	log_info "Installing agent-fork-join plugin..."
	if ! claude plugin install agent-fork-join --scope project 2>&1; then
		log_error "Failed to install plugin"
		# Fallback: show available plugins
		log_info "Available plugins:"
		claude plugin marketplace list 2>&1 || true
		exit 1
	fi

	# Verify the plugin is installed
	log_info "Verifying plugin installation..."
	if claude plugin list 2>&1 | grep -q "agent-fork-join"; then
		log_success "Plugin agent-fork-join installed successfully"
	else
		log_warn "Plugin may not be listed but installation succeeded"
	fi

	log_success "Plugin installed via claude plugin command"
}

# Create the test prompt
# IMPORTANT: This prompt DOES mention git operations because we need 5 separate commits.
# The plugin's UserPromptSubmit hook creates the feature branch.
# Each agent must commit its own work to ensure 5 commits minimum.
# The plugin's session-complete hook creates the PR.
create_test_prompt() {
	cat <<'EOF'
TASK: Create 5 TypeScript modules using the Task tool with 5 parallel subagents.

You MUST spawn 5 coder agents in parallel using the Task tool. Each agent creates ONE file and commits it.

CRITICAL REQUIREMENTS:
1. Use Task tool with subagent_type="coder" for each file
2. Each agent MUST commit its own work with an Angular-style commit message
3. All 5 Task tool calls must be in a SINGLE message (parallel execution)

Here are the 5 tasks to spawn. Copy the EXACT prompt text for each task:

---
TASK 1 PROMPT (copy exactly):
Create the file src/auth/index.ts with this content:
```typescript
export function authenticate(token: string): boolean {
  return token.length > 0;
}
```
After creating the file, run this bash command:
git add src/auth/index.ts && git commit -m "feat(auth): add authenticate function"
---

---
TASK 2 PROMPT (copy exactly):
Create the file src/api/index.ts with this content:
```typescript
export function handleRequest(req: any): any {
  return { status: 'ok', data: req };
}
```
After creating the file, run this bash command:
git add src/api/index.ts && git commit -m "feat(api): add handleRequest function"
---

---
TASK 3 PROMPT (copy exactly):
Create the file src/db/index.ts with this content:
```typescript
export function query(sql: string): any[] {
  return [{ sql }];
}
```
After creating the file, run this bash command:
git add src/db/index.ts && git commit -m "feat(db): add query function"
---

---
TASK 4 PROMPT (copy exactly):
Create the file src/utils/index.ts with this content:
```typescript
export function log(msg: string): void {
  console.log(msg);
}
```
After creating the file, run this bash command:
git add src/utils/index.ts && git commit -m "feat(utils): add log function"
---

---
TASK 5 PROMPT (copy exactly):
Create the file src/config/index.ts with this content:
```typescript
export function getConfig(): any {
  return { env: 'development' };
}
```
After creating the file, run this bash command:
git add src/config/index.ts && git commit -m "feat(config): add getConfig function"
---

NOW: Call all 5 Task tools in parallel in your next response. Use subagent_type="coder" for each.
EOF
}

# Check if feature branch exists on remote (Angular commit types: feat/, fix/, refactor/, etc.)
# Valid Angular types: build, ci, docs, feat, fix, perf, refactor, test
check_remote_branch() {
	local branch_pattern="$1"
	gh api "repos/${FULL_REPO}/branches" 2>/dev/null | jq -r '.[].name' | grep -qE "^(build|ci|docs|feat|fix|perf|refactor|test)/" 2>/dev/null
}

# Monitor for branch creation in background
monitor_branch_creation() {
	local timeout_secs="$1"
	local check_interval=15
	local elapsed=0

	while [[ $elapsed -lt $timeout_secs ]]; do
		if check_remote_branch "feature/"; then
			echo "BRANCH_CREATED"
			return 0
		fi
		sleep $check_interval
		elapsed=$((elapsed + check_interval))
		log_info "Waiting for feature branch... (${elapsed}s/${timeout_secs}s)"
	done

	echo "BRANCH_TIMEOUT"
	return 1
}

# Run Claude with the test prompt
run_claude_test() {
	log_info "Running Claude with test prompt..."

	local prompt
	prompt="$(create_test_prompt)"

	# Set up log files
	mkdir -p "${LOG_DIR}"
	local stdout_log="${LOG_DIR}/${REPO_NAME}-claude-stdout.log"
	local stderr_log="${LOG_DIR}/${REPO_NAME}-claude-stderr.log"
	local combined_log="${LOG_DIR}/${REPO_NAME}-claude.log"

	# Build scoped permission patterns for the test directory
	# These allow only the specific operations needed for the test
	local allowed_tools=(
		# File operations scoped to test directory
		"Read(${TEST_DIR}/**)"
		"Write(${TEST_DIR}/**)"
		"Edit(${TEST_DIR}/**)"
		"Glob(${TEST_DIR}/**)"
		"Grep(${TEST_DIR}/**)"
		"LS(${TEST_DIR}/**)"
		# Bash commands needed for git, gh, and validation
		"Bash(git *)"
		"Bash(gh pr *)"
		"Bash(gh repo *)"
		"Bash(gh auth *)"
		"Bash(npm test)"
		"Bash(npm run *)"
		"Bash(mkdir *)"
		"Bash(ls *)"
		"Bash(tree *)"
		"Bash(find *)"
		"Bash(cat *)"
		"Bash(echo *)"
		# Agent spawning (if needed)
		"Task"
	)

	# Join allowed tools with commas
	local allowed_tools_str
	allowed_tools_str=$(
		IFS=,
		echo "${allowed_tools[*]}"
	)

	log_info "Executing Claude with model=${MODEL}..."
	log_info "Logs: ${combined_log}"
	if [[ "${VERBOSE}" == "true" ]]; then
		log_info "Allowed tools: ${allowed_tools_str}"
	fi

	# Start branch monitor in background (2 minute timeout for branch creation)
	local branch_timeout=120
	log_info "Starting branch creation monitor (${branch_timeout}s timeout)..."

	# Run Claude in background with scoped permissions for non-interactive testing
	# IMPORTANT: Must NOT use --dangerously-skip-permissions per test requirements
	# Instead, use --allowedTools with specific scoped permissions
	# Use --permission-mode acceptEdits to auto-accept the scoped tools without prompting
	claude --print --model "${MODEL}" --allowedTools "${allowed_tools_str}" --permission-mode acceptEdits -p "${prompt}" \
		>"${stdout_log}" 2>"${stderr_log}" &
	local claude_pid=$!

	log_info "Claude started with PID ${claude_pid}"

	# Monitor for branch creation while Claude runs
	local branch_check_interval=15
	local elapsed=0
	local branch_found=false

	while kill -0 "${claude_pid}" 2>/dev/null; do
		# Check if branch was created
		if ! $branch_found && check_remote_branch "feature/"; then
			branch_found=true
			log_success "Feature branch detected on remote!"
		fi

		# Check if we've exceeded branch creation timeout without a branch
		if ! $branch_found && [[ $elapsed -ge $branch_timeout ]]; then
			log_error "FAIL: No feature branch created within ${branch_timeout} seconds"
			log_error "Killing Claude process..."
			kill "${claude_pid}" 2>/dev/null || true
			sleep 2
			kill -9 "${claude_pid}" 2>/dev/null || true

			# Combine logs for debugging (including hook debug log)
			{
				echo "=== STDOUT ==="
				cat "${stdout_log}" 2>/dev/null || echo "(empty)"
				echo ""
				echo "=== STDERR ==="
				cat "${stderr_log}" 2>/dev/null || echo "(empty)"
				echo ""
				echo "=== HOOK DEBUG LOG ==="
				cat /tmp/fork-join-hook-debug.log 2>/dev/null || echo "(no hook debug log found)"
			} >"${combined_log}"

			# Copy hook debug log
			cp /tmp/fork-join-hook-debug.log "${LOG_DIR}/${REPO_NAME}-hook-debug.log" 2>/dev/null || true

			log_error "Claude logs saved to: ${combined_log}"
			if [[ "${VERBOSE}" == "true" ]]; then
				log_info "=== Claude Output ==="
				cat "${combined_log}"
			fi
			return 1
		fi

		# Check if we've exceeded total timeout
		if [[ $elapsed -ge $TIMEOUT ]]; then
			log_error "FAIL: Total timeout (${TIMEOUT}s) exceeded"
			kill "${claude_pid}" 2>/dev/null || true
			sleep 2
			kill -9 "${claude_pid}" 2>/dev/null || true

			{
				echo "=== STDOUT ==="
				cat "${stdout_log}" 2>/dev/null || echo "(empty)"
				echo ""
				echo "=== STDERR ==="
				cat "${stderr_log}" 2>/dev/null || echo "(empty)"
			} >"${combined_log}"

			return 1
		fi

		sleep $branch_check_interval
		elapsed=$((elapsed + branch_check_interval))

		# Show progress
		if [[ $((elapsed % 30)) -eq 0 ]]; then
			log_info "Claude running... (${elapsed}s elapsed, branch_found=${branch_found})"
		fi
	done

	# Claude finished, get exit code
	wait "${claude_pid}" 2>/dev/null
	local claude_exit=$?

	# Combine logs (including hook debug log)
	{
		echo "=== STDOUT ==="
		cat "${stdout_log}" 2>/dev/null || echo "(empty)"
		echo ""
		echo "=== STDERR ==="
		cat "${stderr_log}" 2>/dev/null || echo "(empty)"
		echo ""
		echo "=== HOOK DEBUG LOG ==="
		cat /tmp/fork-join-hook-debug.log 2>/dev/null || echo "(no hook debug log found)"
	} >"${combined_log}"

	# Copy hook debug log to test logs dir
	cp /tmp/fork-join-hook-debug.log "${LOG_DIR}/${REPO_NAME}-hook-debug.log" 2>/dev/null || true

	if [[ $claude_exit -ne 0 ]]; then
		log_error "Claude exited with code ${claude_exit}"
		if [[ "${VERBOSE}" == "true" ]]; then
			log_info "=== Claude Output ==="
			cat "${combined_log}"
		fi
		return 1
	fi

	# Final branch check
	if ! $branch_found; then
		if check_remote_branch "feature/"; then
			log_success "Feature branch detected on remote!"
		else
			log_error "FAIL: Claude completed but no feature branch was created"
			if [[ "${VERBOSE}" == "true" ]]; then
				log_info "=== Claude Output ==="
				cat "${combined_log}"
			fi
			return 1
		fi
	fi

	log_success "Claude completed successfully"

	if [[ "${VERBOSE}" == "true" ]]; then
		log_info "=== Claude Output ==="
		cat "${combined_log}"
	fi
}

# Verify test results
verify_results() {
	log_info "Verifying test results..."

	local errors=()

	# Check for feature branch
	log_info "Checking for feature branches..."
	local branches
	branches=$(git branch -a 2>/dev/null || echo "")

	local feature_branch=""
	while IFS= read -r branch; do
		# Strip leading asterisk, spaces, and 'remotes/origin/' prefix
		branch=$(echo "${branch}" | sed 's/^[* ]*//' | sed 's/^remotes\/origin\///')
		# Accept Angular commit type prefixes: build, ci, docs, feat, fix, perf, refactor, test
		if [[ "${branch}" =~ ^(build|ci|docs|feat|fix|perf|refactor|test)/ ]]; then
			feature_branch="${branch}"
			break
		fi
	done <<<"${branches}"

	if [[ -z "${feature_branch}" ]]; then
		log_warn "No feature branch found locally, checking remote..."
		branches=$(git ls-remote --heads origin 2>/dev/null || echo "")
		while IFS= read -r line; do
			# Accept Angular commit type prefixes
			if [[ "${line}" =~ refs/heads/((build|ci|docs|feat|fix|perf|refactor|test)/.*) ]]; then
				feature_branch="${BASH_REMATCH[1]}"
				break
			fi
		done <<<"${branches}"
	fi

	if [[ -z "${feature_branch}" ]]; then
		errors+=("No feature branch created")
	else
		log_success "Feature branch found: ${feature_branch}"
	fi

	# Check commit count (looking for at least 2 commits: initial + modules)
	log_info "Checking commit count..."
	local commit_count
	if [[ -n "${feature_branch}" ]]; then
		# Fetch the branch first
		git fetch origin "${feature_branch}" 2>/dev/null || true
		commit_count=$(git rev-list --count "origin/${feature_branch}" 2>/dev/null || echo "0")
	else
		commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "1")
	fi

	if [[ "${commit_count}" -lt 5 ]]; then
		errors+=("Expected at least 5 commits (1 initial + 5 agent commits - 1 possible dedup), found ${commit_count}")
	else
		log_success "Commit count: ${commit_count} (meets minimum of 5)"
	fi

	# Check for PR
	log_info "Checking for pull request..."
	local pr_list
	pr_list=$(gh pr list --repo "${FULL_REPO}" --json number,title,state 2>/dev/null || echo "[]")
	local pr_count
	pr_count=$(echo "${pr_list}" | jq 'length')

	if [[ "${pr_count}" -eq 0 ]]; then
		errors+=("No pull request created")
	else
		local pr_info
		pr_info=$(echo "${pr_list}" | jq -r '.[0] | "#\(.number): \(.title) [\(.state)]"')
		log_success "Pull request found: ${pr_info}"
	fi

	# Check for created directories
	log_info "Checking for created directories..."
	local expected_dirs=("src/auth" "src/api" "src/db" "src/utils" "src/config")
	local missing_dirs=()

	for dir in "${expected_dirs[@]}"; do
		if [[ ! -d "${dir}" ]]; then
			# Check if it exists on remote
			if git ls-tree --name-only -r "origin/${feature_branch:-main}" 2>/dev/null | grep -q "^${dir}/"; then
				log_success "Directory ${dir}/ exists (on remote)"
			else
				missing_dirs+=("${dir}")
			fi
		else
			log_success "Directory ${dir}/ exists"
		fi
	done

	if [[ ${#missing_dirs[@]} -gt 0 ]]; then
		errors+=("Missing directories: ${missing_dirs[*]}")
	fi

	# Print summary
	echo ""
	echo "========================================="
	echo "           TEST RESULTS SUMMARY"
	echo "========================================="
	echo ""
	echo "Repository:     ${FULL_REPO}"
	echo "Feature Branch: ${feature_branch:-N/A}"
	echo "Commits:        ${commit_count}"
	echo "Pull Requests:  ${pr_count}"
	echo ""

	if [[ ${#errors[@]} -eq 0 ]]; then
		log_success "All verifications passed!"
		echo ""
		echo "Repository URL: https://github.com/${FULL_REPO}"
		if [[ "${pr_count}" -gt 0 ]]; then
			local pr_number
			pr_number=$(echo "${pr_list}" | jq -r '.[0].number')
			echo "Pull Request:   https://github.com/${FULL_REPO}/pull/${pr_number}"
		fi
		return 0
	else
		log_error "Test failed with ${#errors[@]} error(s):"
		for err in "${errors[@]}"; do
			echo "  - ${err}"
		done
		return 1
	fi
}

# Main test execution
main() {
	echo ""
	echo "========================================="
	echo "   Agent Fork-Join E2E Test"
	echo "========================================="
	echo ""
	echo "Repository: ${FULL_REPO}"
	echo "Model:      ${MODEL}"
	echo "Timeout:    ${TIMEOUT}s (test fails if exceeded)"
	echo "Clean up:   ${CLEAN_UP}"
	echo ""

	check_prerequisites
	create_test_repo

	cd "${TEST_DIR}"

	run_claude_test

	verify_results

	local result=$?

	if [[ $result -eq 0 ]]; then
		echo ""
		log_success "E2E test completed successfully!"
		if [[ "${CLEAN_UP}" != "true" ]]; then
			echo ""
			echo "The test repository has been kept for inspection."
			echo "Run with --clean to automatically delete it after testing."
		fi
	else
		echo ""
		log_error "E2E test failed!"
		echo "Check logs at: ${LOG_DIR}/${REPO_NAME}-claude.log"
	fi

	return $result
}

main
