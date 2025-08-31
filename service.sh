#!/bin/sh
# Access Service - Stacker Framework Integration
# Clean single-word naming, unified architecture

set -e

# Ensure Stacker is available
if ! command -v stacker >/dev/null 2>&1; then
    echo "ERROR: Stacker framework required but not found" 
    echo "Install: stacker self-install"
    exit 1
fi

# Configure Access for Stacker service management
export STACKER_SERVICE_TYPE="simple"
export STACKER_TECH_NAME="access"
export STACKER_REPO_URL="https://github.com/akaoio/access.git"
export STACKER_MAIN_SCRIPT="access.sh"
export STACKER_SERVICE_DESCRIPTION="Foundational Network Access Layer - Eternal Infrastructure"

# Access = eternal infrastructure - maximum reliability
export STACKER_RESTART_POLICY="always"
export STACKER_RESTART_SEC="5"
export STACKER_AUTO_UPDATE="true"

# Initialize Stacker for Access service
stacker init --template=service --name=access --repo="$STACKER_REPO_URL"

echo "✅ Access service configured via Stacker framework"
echo "⚡ Eternal infrastructure service ready"
echo "Run: stacker service start"