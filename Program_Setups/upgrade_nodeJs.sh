#!/bin/bash

# Usage: sudo ./upgrade_nodeJs.sh [version]
# If version is not provided, installs the latest LTS version of Node.js.
# If a different version is already installed in /opt, it will be removed and replaced.

# Log file location
LOG_FILE="/var/log/node_upgrade.log"

# Create or clear the log file
echo "Node.js Upgrade Log - $(date)" > $LOG_FILE
echo "-----------------------------------" >> $LOG_FILE

set -o pipefail

# If installed before, remove the old system packages with the available package manager
if command -v apt-get >/dev/null 2>&1; then
  apt-get purge -y nodejs npm
elif command -v dnf >/dev/null 2>&1; then
  dnf remove -y nodejs npm
elif command -v yum >/dev/null 2>&1; then
  yum remove -y nodejs npm
else
  echo "Warning: No supported package manager found for removing system Node.js packages." | tee -a $LOG_FILE
fi

# Parse command-line arguments for version
if [ $# -gt 0 ]; then
  NODE_VERSION="$1"
  # Check if it's a major version number (e.g., "20")
  if [[ "$NODE_VERSION" =~ ^[0-9]+$ ]]; then
    # Find the latest version in this major series
    NODE_VERSION=$(curl -s https://nodejs.org/dist/index.json | jq -r "[.[] | select(.version | startswith(\"v${NODE_VERSION}.\"))][0].version" 2>/dev/null)
    if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" = "null" ]; then
      echo "Error: No versions found for major version $1" | tee -a $LOG_FILE
      exit 1
    fi
    echo "Using latest Node.js version in $1.x series: ${NODE_VERSION}" | tee -a $LOG_FILE
  else
    echo "Using specified Node.js version: ${NODE_VERSION}" | tee -a $LOG_FILE
  fi
else
  # Try to detect the latest Node.js LTS version from the official index.json
  DEFAULT_NODE_VERSION="v22.11.0"
  NODE_VERSION=$(curl -s https://nodejs.org/dist/index.json | jq -r '[.[] | select(.lts != false)][0].version' 2>/dev/null || echo "$DEFAULT_NODE_VERSION")
  if [ -z "$NODE_VERSION" ]; then
    NODE_VERSION="$DEFAULT_NODE_VERSION"
  fi
  echo "Using latest LTS Node.js version: ${NODE_VERSION}" | tee -a $LOG_FILE
fi
INSTALL_DIR="/opt"
BIN_DIR="/usr/local/bin"

# Detect system architecture and adapt Node binary suffix
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64)
    NODE_ARCH="x64";
    ;;
  aarch64|arm64)
    NODE_ARCH="arm64";
    ;;
  armv7l|armhf)
    NODE_ARCH="armv7l";
    ;;
  *)
    NODE_ARCH="x64";
    echo "Warning: Unknown architecture $ARCH, falling back to x64" | tee -a $LOG_FILE
    ;;
esac

# Rebuild distro name and URL with architecture
NODE_DISTRO="node-${NODE_VERSION}-linux-${NODE_ARCH}"
NODE_TAR="${NODE_DISTRO}.tar.xz"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_TAR}"
echo "Detected architecture: $ARCH -> using $NODE_ARCH" | tee -a $LOG_FILE

# Remove any existing Node.js installations in /opt before upgrading
if compgen -G "$INSTALL_DIR"/node-* > /dev/null; then
  echo "Removing existing Node.js installations from $INSTALL_DIR..." | tee -a $LOG_FILE
  for node_dir in "$INSTALL_DIR"/node-*; do
    if [ -d "$node_dir" ]; then
      echo "Removing $node_dir..." | tee -a $LOG_FILE
      sudo rm -rf "$node_dir"
    fi
  done
fi

# Step 1: Download and extract the Node.js tarball
echo "Downloading Node.js version ${NODE_VERSION}..." | tee -a $LOG_FILE
echo "Extracting Node.js to $INSTALL_DIR..." | tee -a $LOG_FILE
if ! curl -fsSL "$NODE_URL" | tar -xJf - -C "$INSTALL_DIR"; then
  echo "Error: Failed to download or extract Node.js." | tee -a $LOG_FILE
  exit 1
fi

# Step 2: Create symbolic links for node, npm, and npx
echo "Creating symbolic links for Node.js binaries..." | tee -a $LOG_FILE
sudo ln -sf $INSTALL_DIR/$NODE_DISTRO/bin/node $BIN_DIR/node
sudo ln -sf $INSTALL_DIR/$NODE_DISTRO/bin/npm $BIN_DIR/npm
sudo ln -sf $INSTALL_DIR/$NODE_DISTRO/bin/npx $BIN_DIR/npx
sudo ln -sf $INSTALL_DIR/$NODE_DISTRO/bin/node $BIN_DIR/nodejs

if [ $? -ne 0 ]; then
  echo "Error: Failed to create symbolic links." | tee -a $LOG_FILE
  exit 1
fi

# Step 3: Test if the binaries are callable and log the result
echo "Testing Node.js, npm, npx, and nodejs..." | tee -a $LOG_FILE

NODE_VERSION_TEST=$(node -v)
NODE_STATUS=$?
NPM_VERSION_TEST=$(npm -v)
NPM_STATUS=$?
NPX_VERSION_TEST=$(npx -v)
NPX_STATUS=$?
NODEJS_VERSION_TEST=$(nodejs -v)
NODEJS_STATUS=$?

if [ $NODE_STATUS -eq 0 ] && [ $NPM_STATUS -eq 0 ] && [ $NPX_STATUS -eq 0 ] && [ $NODEJS_STATUS -eq 0 ]; then
  echo "Node.js version: $NODE_VERSION_TEST" | tee -a $LOG_FILE
  echo "npm version: $NPM_VERSION_TEST" | tee -a $LOG_FILE
  echo "npx version: $NPX_VERSION_TEST" | tee -a $LOG_FILE
  echo "nodejs version: $NODEJS_VERSION_TEST" | tee -a $LOG_FILE
else
  echo "Error: One or more binaries are not callable." | tee -a $LOG_FILE
  exit 1
fi

echo "Node.js upgrade completed successfully." | tee -a $LOG_FILE