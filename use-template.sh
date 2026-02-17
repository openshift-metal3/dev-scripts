#!/bin/bash
################################################################################
## use-template.sh - Activate a config template for dev-scripts
##
## Copies a template from config-templates/ to config_$USER.sh so that
## dev-scripts picks it up automatically. If CI_TOKEN is already set in the
## environment or in an existing config file, it is preserved.
##
## Usage:
##   ./use-template.sh <template-name>    # Copy template to config_$USER.sh
##   ./use-template.sh --list             # List available templates
##   ./use-template.sh --help             # Show this help
##
## Examples:
##   ./use-template.sh ipi-ipv4-compact
##   ./use-template.sh agent-sno-ipv4
##   CI_TOKEN=sha256~xxx ./use-template.sh ipi-ipv4-ha
##
################################################################################

set -euo pipefail

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPTDIR}/config-templates"
TARGET="${SCRIPTDIR}/config_${USER}.sh"
PLACEHOLDER="<insert-your-token-here>"

usage() {
    echo "Usage: $0 <template-name> | --list | --help"
    echo ""
    echo "Copies a deployment template to config_${USER}.sh"
    echo ""
    echo "Options:"
    echo "  --list, -l    List available templates"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "The CI_TOKEN can be provided in three ways (in order of priority):"
    echo "  1. CI_TOKEN environment variable"
    echo "  2. Existing CI_TOKEN in current config_${USER}.sh"
    echo "  3. Manual edit after template is copied"
    echo ""
    echo "Examples:"
    echo "  $0 ipi-ipv4-compact"
    echo "  CI_TOKEN=sha256~xxxx $0 agent-sno-ipv4"
}

list_templates() {
    echo "Available templates:"
    echo ""
    for template in "${TEMPLATES_DIR}"/*.sh; do
        [ -f "$template" ] || continue
        name=$(basename "$template" .sh)
        # Extract the description from the first non-border ## comment line
        description=$(grep '^##' "$template" | grep -v '^####' | head -1 | sed 's/^## //')
        printf "  %-30s %s\n" "$name" "$description"
    done
    echo ""
    echo "Use '$0 <template-name>' to activate a template."
}

# Extract existing CI_TOKEN from the current config file, if present
get_existing_token() {
    if [ -f "$TARGET" ]; then
        # Match lines like: export CI_TOKEN='...' or export CI_TOKEN="..."
        local token
        token=$(grep -oP "export CI_TOKEN=['\"]?\K[^'\"]*" "$TARGET" 2>/dev/null || true)
        if [ -n "$token" ] && [ "$token" != "$PLACEHOLDER" ]; then
            echo "$token"
        fi
    fi
}

# ---- Main ----

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

case "$1" in
    --help|-h)
        usage
        exit 0
        ;;
    --list|-l)
        list_templates
        exit 0
        ;;
    -*)
        echo "Error: Unknown option '$1'"
        usage
        exit 1
        ;;
esac

TEMPLATE_NAME="$1"
TEMPLATE_FILE="${TEMPLATES_DIR}/${TEMPLATE_NAME}.sh"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template '${TEMPLATE_NAME}' not found."
    echo ""
    list_templates
    exit 1
fi

# Determine the CI_TOKEN to inject
TOKEN=""

# Priority 1: CI_TOKEN from environment
if [ -n "${CI_TOKEN:-}" ]; then
    TOKEN="$CI_TOKEN"
fi

# Priority 2: CI_TOKEN from existing config file
if [ -z "$TOKEN" ]; then
    TOKEN=$(get_existing_token)
fi

# Backup existing config if present
if [ -f "$TARGET" ]; then
    BACKUP="${TARGET}.bak"
    cp "$TARGET" "$BACKUP"
    echo "Backed up existing config to $(basename "$BACKUP")"
fi

# Copy template
cp "$TEMPLATE_FILE" "$TARGET"

# Inject CI_TOKEN if we have one
if [ -n "$TOKEN" ]; then
    sed -i "s|${PLACEHOLDER}|${TOKEN}|g" "$TARGET"
    if [ -n "${CI_TOKEN:-}" ]; then
        echo "CI_TOKEN has been set from environment variable."
    else
        echo "CI_TOKEN has been preserved from existing config."
    fi
else
    echo ""
    echo "WARNING: CI_TOKEN is not set."
    echo "  Edit ${TARGET} and replace '${PLACEHOLDER}' with your token."
    echo "  Get your token from: https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/"
    echo ""
fi

echo "Template '${TEMPLATE_NAME}' activated as $(basename "$TARGET")"
echo ""

# Show a summary of what was configured
echo "Configuration summary:"
grep -E "^export " "$TARGET" | grep -v "CI_TOKEN" | sed 's/^export /  /'
