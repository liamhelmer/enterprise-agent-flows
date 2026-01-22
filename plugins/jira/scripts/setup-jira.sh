#!/bin/bash
# JIRA Integration Setup Script
# This script checks prerequisites and configures JIRA integration with beads

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
DEFAULT_JIRA_URL="https://badal.atlassian.net"
DEFAULT_GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

# Output functions
info() {
	echo -e "${BLUE}$1${NC}"
}

success() {
	echo -e "${GREEN}$1${NC}"
}

warning() {
	echo -e "${YELLOW}$1${NC}"
}

error() {
	echo -e "${RED}$1${NC}"
}

# Check prerequisites
check_prerequisites() {
	local missing=0

	echo "=== Checking Prerequisites ==="
	echo ""

	# Check JIRA_API_TOKEN
	if [[ -z "$JIRA_API_TOKEN" ]]; then
		error "JIRA_API_TOKEN: Not set"
		missing=1
	else
		success "JIRA_API_TOKEN: Set"
	fi

	# Check beads CLI
	if command -v bd &>/dev/null; then
		local bd_version
		bd_version=$(bd --version 2>/dev/null | head -1 || echo "unknown")
		success "beads CLI: Installed ($bd_version)"
	else
		error "beads CLI: Not installed"
		missing=1
	fi

	echo ""

	if [[ $missing -eq 1 ]]; then
		return 1
	fi

	return 0
}

# Show instructions for missing JIRA_API_TOKEN
show_token_instructions() {
	echo ""
	warning "Missing: JIRA_API_TOKEN environment variable"
	echo ""
	echo "To get your API token:"
	echo "1. Go to https://id.atlassian.com/manage-profile/security/api-tokens"
	echo "2. Click \"Create API token\""
	echo "3. Label it (e.g., \"beads-sync\")"
	echo "4. Copy the token"
	echo ""
	echo "Then set it in your environment:"
	echo "  export JIRA_API_TOKEN=\"your_token_here\""
	echo ""
	echo "For persistence, add to your shell profile (~/.bashrc, ~/.zshrc, etc.)"
	echo ""
}

# Show instructions for missing beads CLI
show_beads_instructions() {
	echo ""
	warning "Missing: beads CLI (bd command)"
	echo ""
	echo "Install beads:"
	echo "  go install github.com/beads-dev/beads/cmd/bd@latest"
	echo ""
	echo "Or download from: https://github.com/beads-dev/beads/releases"
	echo ""
}

# Initialize beads if needed
init_beads() {
	if [[ ! -d ".beads" ]]; then
		info "Initializing beads..."
		bd init
		echo ""
	else
		info "beads already initialized"
	fi
}

# Run beads doctor
run_doctor() {
	info "Running beads diagnostics..."
	bd doctor --fix 2>/dev/null || true
	echo ""
}

# Configure JIRA settings
configure_jira() {
	local url="$1"
	local project="$2"
	local label="$3"
	local username="$4"

	info "Configuring JIRA integration..."
	echo ""

	bd config set jira.url "$url"
	echo "  jira.url = $url"

	bd config set jira.project "$project"
	echo "  jira.project = $project"

	if [[ -n "$label" ]]; then
		bd config set jira.label "$label"
		echo "  jira.label = $label"
	fi

	bd config set jira.username "$username"
	echo "  jira.username = $username"

	echo ""
}

# Perform initial sync
initial_sync() {
	info "Syncing with JIRA..."
	if bd jira sync --pull; then
		success "Sync completed successfully"
	else
		warning "Sync completed with warnings (check bd jira status)"
	fi
	echo ""
}

# Show summary
show_summary() {
	local url="$1"
	local project="$2"
	local label="$3"
	local username="$4"

	echo "=== Setup Complete ==="
	echo ""
	echo "Your beads instance is now connected to JIRA."
	echo ""
	echo "Configuration:"
	echo "  URL:      $url"
	echo "  Project:  $project"
	if [[ -n "$label" ]]; then
		echo "  Label:    $label"
	fi
	echo "  Username: $username"
	echo ""
	echo "Useful commands:"
	echo "  bd jira sync --pull   # Pull issues from JIRA"
	echo "  bd jira sync --push   # Push issues to JIRA"
	echo "  bd jira sync          # Bidirectional sync"
	echo "  bd jira status        # Check sync status"
	echo "  bd list               # List local issues"
	echo ""
}

# Main function
main() {
	echo ""
	echo "=== JIRA Integration Setup ==="
	echo ""

	# Check prerequisites
	if ! check_prerequisites; then
		# Show instructions for what's missing
		if [[ -z "$JIRA_API_TOKEN" ]]; then
			show_token_instructions
		fi

		if ! command -v bd &>/dev/null; then
			show_beads_instructions
		fi

		echo "After resolving the above, run /jira-setup again."
		exit 1
	fi

	# Show defaults
	info "Defaults detected:"
	echo "  JIRA URL: $DEFAULT_JIRA_URL"
	if [[ -n "$DEFAULT_GIT_EMAIL" ]]; then
		echo "  Username: $DEFAULT_GIT_EMAIL (from git config)"
	else
		echo "  Username: (not found in git config)"
	fi
	echo ""

	# If running non-interactively, require at least project key
	# URL and username can use defaults
	if [[ $# -lt 1 ]]; then
		echo "Usage: $0 <project_key> [jira_url] [username] [label]"
		echo ""
		echo "Arguments:"
		echo "  project_key  - JIRA project key (required, e.g., PROJ)"
		echo "  jira_url     - JIRA URL (default: $DEFAULT_JIRA_URL)"
		echo "  username     - JIRA email (default: $DEFAULT_GIT_EMAIL)"
		echo "  label        - Optional label filter"
		echo ""
		echo "Examples:"
		echo "  $0 PGF                                    # Use all defaults"
		echo "  $0 PGF https://other.atlassian.net        # Custom URL"
		echo "  $0 PGF \"\" other@email.com DevEx          # Custom username and label"
		exit 1
	fi

	local project_key="$1"
	local jira_url="${2:-$DEFAULT_JIRA_URL}"
	local username="${3:-$DEFAULT_GIT_EMAIL}"
	local label="${4:-}"

	# Validate username is set
	if [[ -z "$username" ]]; then
		error "Username is required but could not be determined from git config."
		echo "Please provide username as third argument."
		exit 1
	fi

	# Initialize beads
	init_beads

	# Run doctor
	run_doctor

	# Configure JIRA
	configure_jira "$jira_url" "$project_key" "$label" "$username"

	# Initial sync
	initial_sync

	# Show summary
	show_summary "$jira_url" "$project_key" "$label" "$username"
}

# Run main
main "$@"
