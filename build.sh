#!/usr/bin/env bash
# Copyright (c) 2025 Alex Goodkind (alex@goodkind.io)
# License: Apache-2.0
#
# ENTRYPOINT: Master build script for ELK Stack LXC Template
#
# This script provides a simple command-line interface to build various
# outputs. It delegates to the Makefile for actual build orchestration.
#
# Usage:
#   ./build.sh installer         Build installer files (default)
#   ./build.sh ct-wrapper        Build CT wrapper only
#   ./build.sh template          Build LXC template
#   ./build.sh clean             Remove generated files
#   ./build.sh test              Run test suite
#   ./build.sh help              Show detailed help

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default target
TARGET="${1:-installer}"

# Validate target
case "$TARGET" in
    installer|ct-wrapper|template|clean|test|help)
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Valid targets: installer, ct-wrapper, template, clean, test, help"
        exit 1
        ;;
esac

# Forward to Makefile
make "$TARGET"

