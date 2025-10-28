#!/bin/bash
# Copyright (c) 2025 Alex Goodkind
# Author: Alex Goodkind (agoodkind)
# License: Apache-2.0

set -e

# Update system and install dependencies
apt update && apt upgrade -y

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source and execute installation steps
# For template build, we use config files from /tmp/elk-config
# The install-steps.sh contains the core logic used by both template and community script
source "${SCRIPT_DIR}/install-steps.sh"

# Clean up temp config directory
rm -rf /tmp/elk-config
