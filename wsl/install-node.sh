#!/usr/bin/env bash
set -euo pipefail

# Check if node is already installed
if command -v node &>/dev/null; then
    echo "Node.js is already installed:"
    node --version
    exit 0
fi

# Check if NVM is installed
NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    echo "NVM not found. Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

# Source NVM
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    source "$NVM_DIR/nvm.sh"
else
    echo "Failed to source NVM" >&2
    exit 1
fi

# Install latest LTS Node
echo "Installing latest LTS Node.js..."
nvm install --lts

# Set default alias
nvm alias default lts/*

# Verify installation
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)

# Echo success message
echo "Node.js installation successful!"
echo "Node version: $NODE_VERSION"
echo "NPM version: $NPM_VERSION"

exit 0
